// OSN-043 window chrome and OSN-041 app-owned alerts, on the real AppDelegate launch.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var windowChromeCases: [(String, () throws -> Void)] { [] }
}
#endif
