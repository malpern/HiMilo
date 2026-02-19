@testable import HiMiloCore
import Testing

struct CLIContextTests {
    @Test func initWithDefaults() {
        let ctx = CLIContext(text: "hello", audioOnly: false, voice: "onyx")
        #expect(ctx.text == "hello")
        #expect(!ctx.audioOnly)
        #expect(ctx.voice == "onyx")
        #expect(!ctx.listen)
        #expect(ctx.port == 4140)
        #expect(!ctx.verbose)
    }

    @Test func initWithAllParameters() {
        let ctx = CLIContext(text: nil, audioOnly: true, voice: "nova", listen: true, port: 8080, verbose: true)
        #expect(ctx.text == nil)
        #expect(ctx.audioOnly)
        #expect(ctx.voice == "nova")
        #expect(ctx.listen)
        #expect(ctx.port == 8080)
        #expect(ctx.verbose)
    }

    @Test func textCanBeNil() {
        let ctx = CLIContext(text: nil, audioOnly: false, voice: "onyx")
        #expect(ctx.text == nil)
    }
}
