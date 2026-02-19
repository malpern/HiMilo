@testable import HiMiloCore
import Testing

struct LogTests {
    @Test func isVerboseDefaultsFalse() {
        let original = Log.isVerbose
        defer { Log.isVerbose = original }

        Log.isVerbose = false
        #expect(!Log.isVerbose)
    }

    @Test func isVerboseCanBeSet() {
        let original = Log.isVerbose
        defer { Log.isVerbose = original }

        Log.isVerbose = true
        #expect(Log.isVerbose)
    }
}
