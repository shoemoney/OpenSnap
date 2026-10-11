// Placeholder until the behaviour tests land: proves the suite wiring compiles.
#if GLASS_CHOICES_TESTS
import AppKit

@main
@MainActor
private enum GlassChoicesTests {
    static func main() {
        _ = NSApplication.shared
        print("glass-choices-tests: skeleton")
    }
}
#endif
