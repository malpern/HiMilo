import Foundation
import os

/// Network binding mode for the listener.
public enum NetworkBindMode: String, CaseIterable, Sendable {
    case localhost  // 127.0.0.1 only (default, most secure)
    case lan        // 0.0.0.0 all interfaces (requires auth token)
}

/// Rate limiter using token bucket algorithm.
@MainActor
final class RateLimiter {
    private struct Bucket {
        var tokens: Int
        var lastRefill: Date
    }
    
    private var buckets: [String: Bucket] = [:]
    private let tokensPerMinute: Int
    private let tokensPerHour: Int
    private let refillInterval: TimeInterval = 60.0  // 1 minute
    
    init(tokensPerMinute: Int = 10, tokensPerHour: Int = 100) {
        self.tokensPerMinute = tokensPerMinute
        self.tokensPerHour = tokensPerHour
    }
    
    /// Check if the given identifier (IP address) is allowed to make a request.
    /// Returns (allowed: Bool, retryAfterSeconds: Int?)
    func checkLimit(for identifier: String) -> (allowed: Bool, retryAfterSeconds: Int?) {
        let now = Date()
        var bucket = buckets[identifier] ?? Bucket(tokens: tokensPerMinute, lastRefill: now)
        
        // Refill tokens based on time elapsed
        let elapsed = now.timeIntervalSince(bucket.lastRefill)
        if elapsed >= refillInterval {
            let periodsElapsed = Int(elapsed / refillInterval)
            bucket.tokens = min(tokensPerMinute, bucket.tokens + (periodsElapsed * tokensPerMinute))
            bucket.lastRefill = now
        }
        
        // Check if token available
        if bucket.tokens > 0 {
            bucket.tokens -= 1
            buckets[identifier] = bucket
            return (true, nil)
        } else {
            // Calculate retry-after
            let nextRefill = bucket.lastRefill.addingTimeInterval(refillInterval)
            let retryAfter = Int(ceil(nextRefill.timeIntervalSince(now)))
            return (false, retryAfter)
        }
    }
    
    /// Reset all buckets (for testing or admin override)
    func reset() {
        buckets.removeAll()
    }
}

/// Bearer token management utilities.
public enum NetworkAuthToken {
    /// Generate a cryptographically secure random token.
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            // Fallback to UUID if SecRandomCopyBytes fails
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Extract bearer token from Authorization header.
    /// Returns nil if header is missing or malformed.
    public static func extractToken(from authHeader: String?) -> String? {
        guard let header = authHeader?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        
        // Expected format: "Bearer <token>"
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2,
              parts[0].lowercased() == "bearer" else {
            return nil
        }
        
        return String(parts[1]).trimmingCharacters(in: .whitespaces)
    }
}
