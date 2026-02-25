# VoxClaw Security Audit

**Audited:** 2026-02-25  
**Auditor:** Sigyn (OpenClaw agent)  
**Focus:** Network security for LAN TTS service

## Summary

VoxClaw is a network TTS service that listens on port 4140 and speaks text sent from remote machines. The core functionality is sound, but the **network layer has significant security gaps** for LAN deployment:

1. ❌ **No authentication** — Anyone on the LAN can trigger speech
2. ❌ **Binds to all interfaces (0.0.0.0)** — Exposed to entire network
3. ⚠️ **CORS-only protection** — Useless against curl/scripts
4. ❌ **No rate limiting** — Spam/abuse vector
5. ✅ **Input validation** — Good (50k chars, 1MB max)
6. ✅ **API key storage** — Keychain (secure)

## Detailed Findings

### 1. No Authentication on /read Endpoint

**File:** `Sources/VoxClawCore/Network/NetworkSession.swift`  
**Issue:** The `/read` endpoint accepts any POST request without authentication.

```swift
private func handleRead(raw: String, initialData: Data) {
    // No auth check here
    let contentLength = HTTPRequestParser.parseContentLength(from: raw)
    // ... proceeds to process request
}
```

**Impact:**
- Anyone on the LAN can trigger speech
- Prank/abuse vector (neighbor sends inappropriate text)
- No way to distinguish legitimate agents from attackers

**Recommendation:** Add bearer token authentication.

### 2. Binds to All Interfaces

**File:** `Sources/VoxClawCore/Network/NetworkListener.swift`  
**Issue:** NWListener binds to `0.0.0.0` (all interfaces) by default.

```swift
let params = NWParameters.tcp
params.allowLocalEndpointReuse = true
guard let nwPort = NWEndpoint.Port(rawValue: port) else { ... }
listener = try NWListener(using: params, on: nwPort)
```

**Impact:**
- Service is exposed to entire network (home LAN, coffee shop WiFi, etc.)
- Should default to localhost-only for single-machine use
- Advanced users can opt-in to LAN binding

**Recommendation:** Add config option:
```swift
enum BindMode {
    case localhost  // 127.0.0.1 only (default)
    case lan        // 0.0.0.0 (all interfaces)
}
```

### 3. CORS Headers Don't Protect Against Scripts

**File:** `Sources/VoxClawCore/Network/NetworkSession.swift`  
**Issue:** CORS headers only protect browser-based requests.

```swift
headers += "Access-Control-Allow-Origin: http://localhost\r\n"
headers += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
```

**Impact:**
- curl, Python requests, and any non-browser client bypass CORS
- Creates false sense of security

**Recommendation:** Don't rely on CORS for access control. Use bearer tokens.

### 4. No Rate Limiting

**File:** `Sources/VoxClawCore/Network/NetworkSession.swift`  
**Issue:** No throttling on `/read` requests.

**Impact:**
- Attacker can spam TTS requests (annoyance attack)
- Could overwhelm OpenAI/ElevenLabs API quota
- No protection against accidental loops

**Recommendation:** Add token bucket rate limiter:
- 10 requests/minute per IP (global)
- 100 requests/hour per IP
- Configurable limits

### 5. Input Validation (Good ✅)

**File:** `Sources/VoxClawCore/Network/HTTPRequestParser.swift`

```swift
static let maxRequestSize = 1_000_000  // 1 MB
static let maxTextLength = 50_000      // 50k chars
```

**Assessment:** Well-designed limits prevent memory exhaustion.

### 6. API Key Storage (Good ✅)

**File:** References to Keychain throughout  
**Assessment:** OpenAI/ElevenLabs keys stored in macOS Keychain. Secure.

## Attack Scenarios

### Scenario 1: Coffee Shop Prank
- Victim opens VoxClaw in listener mode at Starbucks
- Attacker on same WiFi network: `curl -X POST http://victim-ip:4140/read -d "inappropriate text"`
- Victim's Mac speaks aloud

**Mitigation:** Localhost-only binding by default + bearer token

### Scenario 2: Home LAN Spam
- Family member discovers `/read` endpoint
- Scripts 100 requests/second to annoy victim
- Eats OpenAI quota

**Mitigation:** Rate limiting + token auth

### Scenario 3: Accidental Exposure
- User forgets VoxClaw is running
- Port forwarding accidentally exposes 4140 to internet
- Anyone can trigger speech

**Mitigation:** Token auth makes accidental exposure less dangerous

## Proposed Security Hardening

### Phase 1: Auth & Localhost Binding (Critical)

1. **Add bearer token to `/read` endpoint**
   - Generate random token on first launch (store in Keychain)
   - Require `Authorization: Bearer <token>` header
   - Return 401 Unauthorized if missing/invalid
   - Add `--token` flag to CLI for manual override

2. **Add bind mode config**
   - Default: `localhost` (127.0.0.1 only)
   - Setting: "Allow LAN connections" checkbox
   - When enabled: bind to 0.0.0.0

### Phase 2: Rate Limiting (Important)

1. **Implement token bucket per-IP**
   - 10 requests/minute
   - 100 requests/hour
   - Return 429 Too Many Requests when exceeded

2. **Add global circuit breaker**
   - If >50 requests in 10 seconds from ANY source, stop listener
   - Require manual restart

### Phase 3: Observability (Nice-to-have)

1. **Request logging**
   - Log source IP, timestamp, text length, voice
   - Save to `~/Library/Logs/VoxClaw/requests.log`

2. **Security notifications**
   - macOS notification on first connection from new IP
   - "VoxClaw received speech request from 192.168.1.50"

## OpenClaw Integration Requirements

For OpenClaw skill wrapper (`~/.agents/skills/voxclaw-remote-tts/`):

1. **Token management**
   - Read token from Keychain on setup
   - Include in all `/read` requests: `-H "Authorization: Bearer $TOKEN"`

2. **Permission integration**
   - Check schedule (no TTS during sleep hours)
   - Check presence detection (no TTS if human not home)
   - Voice mapping (Saskia → Tessa, Sigyn → Opus)

3. **Error handling**
   - 401 → "VoxClaw auth token invalid, run setup"
   - 429 → "Rate limit hit, wait 60 seconds"
   - Connection refused → "VoxClaw not running on Mac"

## Risk Assessment

**Current Risk Level:** Medium-High for LAN deployments

**After Hardening:** Low

**Residual Risks:**
- Token leakage (if stored in plaintext config)
- Malicious process on Mac can read Keychain
- Physical access to Mac

## Recommendations

### Must-Have (Block merge without these)
- [ ] Bearer token authentication on `/read`
- [ ] Localhost-only binding by default
- [ ] Rate limiting (10 req/min, 100 req/hour)

### Should-Have (Merge but track in issues)
- [ ] Request logging
- [ ] Security notifications for new IPs
- [ ] Token rotation mechanism

### Nice-to-Have (Future work)
- [ ] mTLS for paranoid mode
- [ ] IP allowlist/blocklist
- [ ] Audit log export

## Conclusion

VoxClaw is a well-designed tool with good input validation and API key storage, but the **network layer needs auth and rate limiting** before it's safe for LAN deployment. The proposed hardening is straightforward and won't break existing workflows.

**Recommendation:** Implement Phase 1 (auth + localhost binding) before merging to main.
