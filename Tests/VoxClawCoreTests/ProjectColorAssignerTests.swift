@testable import VoxClawCore
import Testing

struct ProjectColorAssignerTests {

    @Test func sameProjectIdProducesSameIndex() {
        let id = "/Users/me/Code/AlphaProject"
        let a = ProjectColorAssigner.paletteIndex(for: id)
        let b = ProjectColorAssigner.paletteIndex(for: id)
        #expect(a == b)
    }

    @Test func differentProjectIdsUsuallyProduceDifferentIndices() {
        // Walk a bunch of fake project ids; expect at least 6 distinct slots
        // hit (palette has 12). Guards against a hash regression that
        // collapses everything into one bucket.
        let ids = (0..<32).map { "/Users/me/proj/\($0)" }
        let slots = Set(ids.map { ProjectColorAssigner.paletteIndex(for: $0) })
        #expect(slots.count >= 6)
    }

    @Test func indexAlwaysWithinPaletteBounds() {
        for i in 0..<200 {
            let idx = ProjectColorAssigner.paletteIndex(for: "fixture-\(i)")
            #expect(idx >= 0)
            #expect(idx < ProjectColorAssigner.palette.count)
        }
    }

    @Test func emptyStringStillReturnsValidIndex() {
        let idx = ProjectColorAssigner.paletteIndex(for: "")
        #expect(idx >= 0 && idx < ProjectColorAssigner.palette.count)
    }

    // MARK: - displayName

    @Test func displayNameReturnsPathBasename() {
        #expect(ProjectColorAssigner.displayName(for: "/Users/me/code/VoxClaw") == "VoxClaw")
        #expect(ProjectColorAssigner.displayName(for: "/Users/me/code/kindaVimTutor") == "kindaVimTutor")
    }

    @Test func displayNameTrimsTrailingSlash() {
        #expect(ProjectColorAssigner.displayName(for: "/Users/me/code/VoxClaw/") == "VoxClaw")
    }

    @Test func displayNameHandlesNonPathIdentifiers() {
        #expect(ProjectColorAssigner.displayName(for: "alpha-project") == "alpha-project")
    }

    @Test func displayNameTrimsWhitespace() {
        #expect(ProjectColorAssigner.displayName(for: "  /tmp/foo  ") == "foo")
    }
}
