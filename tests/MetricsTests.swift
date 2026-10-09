// Pure value checks: no AppKit drawing, windows or desktop input.
// rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D METRICS_TESTS \
//   Sources/DesignTokens.swift tests/MetricsTests.swift -o /tmp/opensnap-metrics-tests
#if METRICS_TESTS
import AppKit

@main
private enum MetricsTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    static func main() throws {
        typealias D = DesignTokens
        try expect(D.Space.all == [4, 8, 12, 16, 24, 32], "space scale is 4, 8, 12, 16, 24, 32, got \(D.Space.all)")
        try expect(D.Space.all.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 && $0 > 0 }, "every Space value is a positive multiple of 4")
        try expect(D.Space.all == D.Space.all.sorted(), "space scale ascends")

        try expect(D.Radius.all == [4, 8, 12, 16], "radius scale is 4, 8, 12, 16")
        try expect(D.Radius.concentric(outer: D.Radius.xl, inset: D.Space.s1) == 12, "xl group with a 4 pt inset gives lg buttons")
        try expect(D.Radius.concentric(outer: 4, inset: 10) == D.Radius.sm, "concentric clamps at sm")
        for outer in stride(from: CGFloat(0), through: 40, by: 2) {
            for inset in stride(from: CGFloat(0), through: 40, by: 2) {
                try expect(D.Radius.concentric(outer: outer, inset: inset) >= D.Radius.sm, "concentric(\(outer), \(inset)) fell below sm")
            }
        }

        try expect(D.Size.control == 36 && D.Size.field == 40 && D.Size.row == 44 && D.Size.hitMin == 36, "control, field, row, hitMin")
        try expect(D.Size.tool == CGSize(width: 44, height: 40) && D.Size.primary == CGSize(width: 56, height: 44), "tool and primary")
        try expect(D.Size.icon == CGSize(width: 48, height: 36), "icon stays 48 x 36, the current GlassChrome tile, so adoption moves no pixel")
        for (name, size) in [("tool", D.Size.tool), ("primary", D.Size.primary), ("icon", D.Size.icon)] {
            try expect(size.width >= D.Size.hitMin && size.height >= D.Size.hitMin, "\(name) is under the 36 pt hit target")
        }
        try expect(D.Size.field >= D.Size.control && D.Size.row >= D.Size.field, "control <= field <= row")

        try expect(D.Layout.margin == 12, "margin is 12, not Space.s4: the rail-removal width budget depends on it")
        try expect(D.Layout.gap == 8 && D.Layout.header == 44 && D.Layout.footer == 44 && D.Layout.groupGap == 12, "gap, header, footer, groupGap")
        print("MetricsTests: \(checks) checks passed")
    }
}
#endif
