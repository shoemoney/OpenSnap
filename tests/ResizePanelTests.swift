// Pure tests only: no windows, application launch, desktop input, or permissions.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -target arm64-apple-macosx13.0 \
//   -D RESIZE_PANEL_TESTS Sources/ResizePresets.swift Sources/ResizePanel.swift tests/ResizePanelTests.swift \
//   -o /tmp/opensnap-resize-panel-tests
// rtk proxy /tmp/opensnap-resize-panel-tests
#if RESIZE_PANEL_TESTS
import Foundation
import CoreGraphics

@main
@MainActor
private enum ResizePanelTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
        checks += 1
    }

    private static func rejects(_ body: () throws -> Void) throws {
        do { try body() }
        catch is ResizePanelValidation.Failure { checks += 1; return }
        throw Failure(description: "Invalid dimension request was accepted")
    }

    static func main() throws {
        for text in ["", " ", "0", "-1", "+10", "1.5", "10px", "1e2", "1,000", "nan", "inf",
                     "Infinity", "16385", "9999999999999999999999999", "١٢", "１２", "12 3"] {
            try rejects { _ = try ResizePanelValidation.dimension(from: text) }
        }
        try expect(try ResizePanelValidation.dimension(from: " 00120\n") == 120, "Trimmed integer")
        try expect(try ResizePanelValidation.dimension(from: "16384") == 16384, "Maximum dimension")
        for value: CGFloat in [0, -1, .nan, .infinity, -.infinity, 1.25, 16_385,
                               .greatestFiniteMagnitude] {
            try rejects { _ = try ResizePanelValidation.validate(CGSize(width: value, height: 1)) }
            try rejects { _ = try ResizePanelValidation.validate(CGSize(width: 1, height: value)) }
            _ = ResizePanelValidation.text(for: value) // No trapping Int conversion.
        }
        try expect(try ResizePanelValidation.validate(CGSize(width: 8000, height: 4000))
                   == CGSize(width: 8000, height: 4000), "Inclusive 32M pixel boundary")
        try rejects { _ = try ResizePanelValidation.size(width: "8000", height: "4001") }
        try rejects { _ = try ResizePanelValidation.size(width: "16384", height: "16384") }
        try expect(try ResizePanelValidation.size(width: "1", height: "16384")
                   == CGSize(width: 1, height: 16384), "Extreme legal aspect ratio")

        var state = ResizePanelState(size: CGSize(width: 800, height: 600))
        try expect(state.mode == .resize && state.preserveRatio && state.locksProportions,
                   "Original default: resize with proportions locked")
        try expect(state.anchor == .center, "Original default: centered anchor")
        state.edit(.width, text: "400")
        try expect(try state.submission().size == CGSize(width: 400, height: 300), "Width drives ratio")
        state.edit(.height, text: "150")
        try expect(try state.submission().size == CGSize(width: 200, height: 150), "Height drives ratio")
        state.edit(.width, text: "bad")
        try expect(state.widthText == "bad" && state.heightText == "150", "Retain invalid input")
        try rejects { _ = try state.submission() }
        state.edit(.width, text: "400")
        state.setPreserveRatio(false)
        state.edit(.height, text: "120")
        try expect(try state.submission().size == CGSize(width: 400, height: 120), "Unlocked dimensions")
        state.setPreserveRatio(true)
        try expect(try state.submission().size == CGSize(width: 160, height: 120), "Relock uses last edit")

        state.setMode(.crop)
        try expect(state.preserveRatio && !state.locksProportions, "Crop suspends resize ratio preference")
        state.edit(.width, text: "320")
        state.edit(.height, text: "90")
        state.anchor = .bottomRight
        try expect(try state.submission() == ResizePanelSubmission(size: CGSize(width: 320, height: 90),
                   isCrop: true, anchor: CGPoint(x: 1, y: 1)), "Independent crop dimensions and payload")
        state.setMode(.resize)
        try expect(state.locksProportions && state.anchor == .bottomRight, "Mode preferences persist")
        try expect(try state.submission().size == CGSize(width: 120, height: 90), "Return to original ratio")
        try expect(try !state.submission().isCrop, "Resize callback flag is false")
        state.setPreserveRatio(false)
        state.setMode(.crop)
        state.edit(.width, text: "250")
        state.setMode(.resize)
        try expect(!state.preserveRatio && state.widthText == "250" && state.heightText == "90",
                   "Unlocked preference survives round trip")

        var rounding = ResizePanelState(size: CGSize(width: 7, height: 3))
        rounding.edit(.width, text: "10")
        try expect(rounding.heightText == "4", "Nearest whole pixel")
        rounding.edit(.height, text: "3")
        try expect(rounding.widthText == "7", "Original ratio prevents rounding drift")
        var extreme = ResizePanelState(size: CGSize(width: 16384, height: 1))
        extreme.edit(.width, text: "1")
        try expect(extreme.heightText == "1", "Subpixel companion occupies one pixel")
        extreme.edit(.height, text: "2")
        try rejects { _ = try extreme.submission() }
        var area = ResizePanelState(size: CGSize(width: 800, height: 400))
        area.edit(.width, text: "8002")
        try rejects { _ = try area.submission() }
        for initial in [CGSize.zero, CGSize(width: CGFloat.nan, height: 12),
                        CGSize(width: 16384, height: 16384)] {
            var invalid = ResizePanelState(size: initial)
            invalid.setPreserveRatio(true)
            try expect(!invalid.locksProportions, "Invalid original cannot produce a ratio")
            try rejects { _ = try invalid.submission() }
            invalid.edit(.width, text: "800")
            invalid.edit(.height, text: "600")
            try expect(try invalid.submission().size == CGSize(width: 800, height: 600), "Recover invalid original")
        }

        // OSN-058 changed this rule on purpose: an untouched fractional source submits what the field shows (13 x 10),
        // while a TYPED 12.5 is still rejected. The fractional original has no usable ratio, so the lock stays off.
        var fractionalSource = ResizePanelState(size: CGSize(width: 12.5, height: 10))
        fractionalSource.setPreserveRatio(true)
        try expect(!fractionalSource.locksProportions, "Fractional original cannot produce a ratio")
        try expect(try fractionalSource.submission().size == CGSize(width: 13, height: 10), "Untouched 12.5 x 10 submits the displayed 13 x 10")
        fractionalSource.edit(.width, text: "12.5")
        try rejects { _ = try fractionalSource.submission() }
        fractionalSource.edit(.width, text: "800")
        fractionalSource.edit(.height, text: "600")
        try expect(try fractionalSource.submission().size == CGSize(width: 800, height: 600), "Recover fractional original")

        let titles = ["Top Left", "Top Center", "Top Right", "Middle Left", "Center", "Middle Right",
                      "Bottom Left", "Bottom Center", "Bottom Right"]
        let points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0),
                                CGPoint(x: 0, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 0.5),
                                CGPoint(x: 0, y: 1), CGPoint(x: 0.5, y: 1), CGPoint(x: 1, y: 1)]
        try expect(ResizePanelAnchor.allCases.count == 9, "Nine crop anchors")
        for (index, anchor) in ResizePanelAnchor.allCases.enumerated() {
            try expect(anchor.title == titles[index] && anchor.point == points[index], "Anchor \(titles[index])")
        }

        var delivered: [ResizePanelSubmission] = []
        var endedSheet = false
        let session = ResizePanelSession(size: CGSize(width: 800, height: 600)) { size, crop, anchor in
            precondition(endedSheet, "Sheet must end before callback")
            delivered.append(ResizePanelSubmission(size: size, isCrop: crop, anchor: anchor))
        }
        session.state.edit(.width, text: "NaN")
        try rejects { _ = try session.apply { endedSheet = true } }
        try expect(!session.isFinished && !endedSheet && delivered.isEmpty, "Invalid input keeps sheet and callback")
        session.state.setMode(.crop)
        session.state.edit(.width, text: "320")
        session.state.edit(.height, text: "240")
        session.state.anchor = .topLeft
        try expect(try session.apply { endedSheet = true }, "Valid apply")
        try expect(delivered == [ResizePanelSubmission(size: CGSize(width: 320, height: 240),
                   isCrop: true, anchor: .zero)], "Exact callback arguments")
        try expect(try !session.apply(), "Second apply rejected")
        session.cancel()
        try expect(delivered.count == 1, "Completion is exactly once")

        let cancelled = ResizePanelSession(size: CGSize(width: 800, height: 600)) { _, _, _ in
            delivered.append(ResizePanelSubmission(size: .zero, isCrop: false, anchor: .zero))
        }
        cancelled.cancel()
        cancelled.cancel()
        try expect(try !cancelled.apply(), "Cancel prevents later apply")
        try expect(delivered.count == 1, "Cancel never calls callback")
        var reentrant: ResizePanelSession!
        reentrant = ResizePanelSession(size: CGSize(width: 100, height: 50)) { _, crop, _ in
            precondition(!crop)
            precondition((try? reentrant.apply()) == false, "Reentrant callback cannot apply twice")
        }
        try expect(try reentrant.apply(), "Reentrant delivery guarded")
        var previews: [ResizePanelSubmission] = []
        var finishes: [Bool] = []
        let previewSession = ResizePanelSession(size: CGSize(width: 800, height: 600),
            onPreview: { previews.append($0) }, onFinish: { finishes.append($0) })
        previewSession.state.edit(.width, text: "400")
        try expect(try previewSession.preview(), "Apply previews without closing")
        try expect(!previewSession.isFinished && previews.count == 1 && finishes.isEmpty,
                   "Preview leaves session open and uncommitted")
        try expect(try previewSession.preview() && previews.count == 1, "Duplicate Apply does not repeat crop")
        previewSession.state.edit(.width, text: "0")
        try rejects { _ = try previewSession.preview() }
        try expect(previews.count == 1 && !previewSession.isFinished, "Invalid preview preserves previous preview")
        previewSession.state.edit(.width, text: "200")
        var sheetEnded = false
        try expect(try previewSession.apply { sheetEnded = true }, "OK previews last edit then commits")
        try expect(sheetEnded && previews.map(\.size) == [CGSize(width: 400, height: 300), CGSize(width: 200, height: 150)]
                   && finishes == [false], "OK delivers current dimensions and one commit")
        previewSession.cancel()
        try expect(try !previewSession.preview() && finishes == [false], "Sheet cleanup cannot cancel accepted changes")
        let cancelledPreview = ResizePanelSession(size: CGSize(width: 800, height: 600),
            onPreview: { previews.append($0) }, onFinish: { finishes.append($0) })
        cancelledPreview.state.edit(.width, text: "320")
        _ = try cancelledPreview.preview()
        cancelledPreview.cancel(); cancelledPreview.cancel()
        try expect(finishes == [false, true] && cancelledPreview.isFinished, "Cancel rolls back exactly once after Apply")
        struct PreviewFailure: Error {}
        let failedPreview = ResizePanelSession(size: CGSize(width: 800, height: 600),
            onPreview: { _ in throw PreviewFailure() }, onFinish: { finishes.append($0) })
        do { _ = try failedPreview.apply(); throw Failure(description: "Failed shell preview committed") }
        catch is PreviewFailure {}
        try expect(!failedPreview.isFinished && failedPreview.lastPreview == nil && finishes == [false, true],
                   "Failed shell crop leaves sheet open and does not commit")
        failedPreview.cancel()
        var nestedPreview: ResizePanelSession!
        nestedPreview = ResizePanelSession(size: CGSize(width: 100, height: 50), onPreview: { _ in
            precondition((try? nestedPreview.preview()) == false)
            precondition((try? nestedPreview.apply()) == false)
        }, onFinish: { _ in })
        try expect(try nestedPreview.preview(), "Reentrant previews and commits are suppressed")
        nestedPreview.cancel()
        var limitState = ResizePanelState(size: CGSize(width: 800, height: 600))
        limitState.setMode(.limit); limitState.limitText = "400"
        try expect(try limitState.submission().size == CGSize(width: 400, height: 300), "Limit longest side shrinks proportionally")
        limitState.limitMode = .height
        try expect(try limitState.submission().size == CGSize(width: 533, height: 400), "Height limit uses current output aspect")
        limitState.limitMode = .width; limitState.limitText = "1600"
        try expect(try limitState.submission().size == CGSize(width: 1600, height: 1200), "Limit allows enlargement")
        limitState.limitText = "0"
        try rejects { _ = try limitState.submission() }
        limitState.limitText = "16384"
        try rejects { _ = try limitState.submission() }
        let unlocked = ResizePanelSubmission(size: CGSize(width: 800, height: 100), isCrop: false, anchor: .zero, constrainProportions: false)
        let expanded = try ResizePanelGeometry.preview(source: CGSize(width: 300, height: 180), output: CGSize(width: 150, height: 90), request: unlocked)
        let expandedRect = expanded.rect ?? .zero
        try expect(expanded.output == unlocked.size && abs(expandedRect.minX + 570) < 0.00001 && abs(expandedRect.minY) < 0.00001
                   && abs(expandedRect.width - 1440) < 0.00001 && abs(expandedRect.height - 180) < 0.00001,
                   "Unlocked Scale fits proportionally then expands centered source; it never stretches")
        let constrained = try ResizePanelGeometry.preview(source: CGSize(width: 300, height: 180), output: CGSize(width: 150, height: 90),
            request: ResizePanelSubmission(size: CGSize(width: 800, height: 100), isCrop: false, anchor: .zero))
        try expect(constrained.rect == nil && constrained.output == CGSize(width: 167, height: 100), "Constrained Scale fits inside both limits")
        let anchored = try ResizePanelGeometry.preview(source: CGSize(width: 300, height: 180), output: CGSize(width: 150, height: 90),
            request: ResizePanelSubmission(size: CGSize(width: 80, height: 60), isCrop: true, anchor: CGPoint(x: 1, y: 1)))
        try expect(anchored.rect == CGRect(x: 140, y: 60, width: 160, height: 120) && anchored.output == CGSize(width: 80, height: 60),
                   "Crop anchor uses initial source/output relationship")
        // R1-003: the sheet opens at the size the title shows (2400 × 1600) while the output is 1517 × 1011; typed pixels map back.
        let own = CGSize(width: 2400, height: 1600), fitted = CGSize(width: 1517, height: 1011)
        let opened = ResizePanelState(size: own)
        try expect(opened.displayWidthText == "2400" && opened.displayHeightText == "1600", "The sheet opens at the size the title shows")
        let untouched = try ResizePanelGeometry.preview(source: own, output: fitted, displayed: own, request: try opened.submission())
        try expect(untouched.output == fitted, "Apply without a change maps 2400 × 1600 back to exactly the output size (\(untouched.output))")
        let halved = try ResizePanelGeometry.preview(source: own, output: fitted, displayed: own,
            request: ResizePanelSubmission(size: CGSize(width: 1200, height: 800), isCrop: false, anchor: .zero))
        try expect(halved.rect == nil && halved.output == CGSize(width: 759, height: 506), "Typing 1200 × 800 asks for half the title size: half the output, halves rounded up (\(halved.output))")
        let cropped = try ResizePanelGeometry.preview(source: own, output: fitted, displayed: own,
            request: ResizePanelSubmission(size: CGSize(width: 600, height: 400), isCrop: true, anchor: CGPoint(x: 0.5, y: 0.5)))
        try expect(cropped.output == CGSize(width: 379, height: 253) && abs((cropped.rect?.width ?? 0) - 600) < 0.5 && abs((cropped.rect?.height ?? 0) - 400) < 0.5,
                   "A crop typed in title pixels keeps 600 × 400 of the source (\(String(describing: cropped.rect)))")
        let same = try ResizePanelGeometry.preview(source: own, output: fitted, displayed: fitted,
            request: ResizePanelSubmission(size: CGSize(width: 800, height: 100), isCrop: false, anchor: .zero))
        let plain = try ResizePanelGeometry.preview(source: own, output: fitted, request: ResizePanelSubmission(size: CGSize(width: 800, height: 100), isCrop: false, anchor: .zero))
        try expect(same.output == plain.output && same.rect == plain.rect, "Fields seeded with the output size behave as before")
        try rejects { _ = try ResizePanelGeometry.preview(source: own, output: fitted, displayed: CGSize(width: 0, height: 1600), request: try opened.submission()) }
        // R4-002: typing the picture's own width on a snap shown smaller asks for the picture itself, not a resample a pixel short, whether the
        // shown size is an exact fit (768 × 540) or a rounded one (996 × 700).
        let snap = CGSize(width: 2560, height: 1800)
        for shown in [CGSize(width: 768, height: 540), CGSize(width: 996, height: 700)] {
            var typing = ResizePanelState(size: shown)
            typing.edit(.width, text: "2560")
            let native = try ResizePanelGeometry.preview(source: snap, output: shown, displayed: shown, atPictureSize: true, request: try typing.submission())
            try expect(native.picture == ResizePicturePlan(scaleTo: nil, crop: nil, size: snap), "Typing 2560 on a snap shown at \(shown) is the picture itself (\(String(describing: native.picture)))")
        }
        // …while a size merely near the picture's is still a resize, and so is a one-pixel step on a small picture.
        let small = CGSize(width: 100, height: 100)
        var step = ResizePanelState(size: small); step.edit(.width, text: "101")
        let stepped = try ResizePanelGeometry.preview(source: small, output: small, displayed: small, atPictureSize: true, request: try step.submission())
        try expect(stepped.picture == ResizePicturePlan(scaleTo: CGSize(width: 101, height: 101), crop: nil, size: CGSize(width: 101, height: 101)), "101 on a 100 square resizes (\(String(describing: stepped.picture)))")
        // A Limit lands on its number even when the partner side rounds down by half a pixel: 1981 × 953 at 1400 pairs 673, and fitting
        // 1981 × 673 by its smaller ratio used to come out 1399 wide.
        for (odd, limitText) in [(CGSize(width: 1981, height: 953), "1400"), (CGSize(width: 2425, height: 900), "1400"), (CGSize(width: 2351, height: 900), "1200")] {
            var limiting = ResizePanelState(size: odd); limiting.setMode(.limit); limiting.limitText = limitText
            let limited = try ResizePanelGeometry.preview(source: odd, output: odd, displayed: odd, atPictureSize: true, request: try limiting.submission())
            try expect(limited.picture?.size.width == CGFloat(Int(limitText)!), "A Limit of \(limitText) on \(odd) lands on \(limitText) wide (\(String(describing: limited.picture)))")
        }
        try expect(ResizePanelValidation.wholePixel(1516.5) == 1517 && ResizePanelValidation.wholePixel(1516.4) == 1516 && ResizePanelValidation.wholePixel(0.2) == 1
                   && ResizePanelValidation.displayText(for: 1516.5) == "1517", "One rounding rule: halves up, never below 1")
        for preset in ResizePreset.builtins {
            var presetState = ResizePanelState(size: CGSize(width: 800, height: 600))
            presetState.selectPreset(preset)
            let selected = try presetState.submission()
            try expect(selected.size == preset.size && !selected.isCrop && selected.constrainProportions == preset.proportions,
                       "Built-in target dimensions/constraint flags survive UI selection: \(preset.name)")
        }
        var customState = ResizePanelState(size: CGSize(width: 800, height: 600))
        let custom = ResizePreset(id: "custom-geometry", name: "Custom", width: 640, height: 400, mode: .crop,
                                  format: 19, anchor: 8, proportions: false, limitSize: 1000, limitMode: .height)
        customState.selectPreset(custom)
        try expect(try customState.preset(id: custom.id, name: custom.name, format: custom.format) == custom,
                   "UI preserves all custom preset fields and opaque format metadata")
        // OSN-058: the fields show whole pixels, rounded half away from zero; only the shown text is rounded.
        for (value, shown) in [(CGFloat(1516.5), "1517"), (1516.4, "1516"), (1516, "1516"), (0.5, "1"), (1515.5, "1516"), (16384, "16384")] as [(CGFloat, String)] {
            try expect(ResizePanelValidation.displayText(for: value) == shown, "\(value) displays as \(shown), got \(ResizePanelValidation.displayText(for: value))")
        }
        for value: CGFloat in [1516.5, 1234.567, 99999.75, 0.25, -3.5, .nan, .infinity, .greatestFiniteMagnitude] {
            let text = ResizePanelValidation.displayText(for: value) // never traps on odd input
            if value.isFinite && abs(value) < 1e15 { try expect(!text.contains("."), "\(value) shows no decimal point, got \(text)") }
        }
        let fractional = ResizePanelState(size: CGSize(width: 1516.5, height: 1000))
        try expect(fractional.displayWidthText == "1517" && fractional.displayHeightText == "1000" && fractional.displayLimitText == "1517",
                   "width, height and limit fields show whole pixels: \(fractional.displayWidthText) x \(fractional.displayHeightText), limit \(fractional.displayLimitText)")
        try expect(fractional.widthText == "1516.5", "the text the validator reads is untouched: \(fractional.widthText)")
        // the stored size is still 1516.5: limit mode scales from it (a size rounded to 1517 first gives a 999 high result)
        var limited = fractional
        limited.setMode(.limit); limited.limitText = "1516"
        try expect(try limited.submission().size == CGSize(width: 1516, height: 1000), "limit math runs on the full-precision 1516.5, got \(try limited.submission().size)")
        var rounded = ResizePanelState(size: CGSize(width: 1517, height: 1000))
        rounded.setMode(.limit); rounded.limitText = "1516"
        try expect(try rounded.submission().size == CGSize(width: 1516, height: 999), "a stored 1517 gives 999 here, so the case above really tells the two apart")
        // typed values pass through untouched and are never re-rounded on display
        var typed = fractional
        typed.edit(.width, text: "1516")
        try expect(typed.widthText == "1516" && typed.displayWidthText == "1516" && (try typed.submission().size.width) == 1516, "a typed 1516 stays 1516")
        typed.edit(.height, text: "1.5")
        try expect(typed.displayHeightText == "1.5", "typed text is shown exactly as typed, not rounded: \(typed.displayHeightText)")
        typed.edit(.height, text: "1000")
        try expect(typed.displayHeightText == "1000" && (try typed.submission().size) == CGSize(width: 1516, height: 1000), "a typed 1000 round-trips")
        var whole = ResizePanelState(size: CGSize(width: 1516, height: 1000))
        try expect(whole.displayWidthText == "1516" && whole.displayHeightText == "1000", "whole-pixel sources display unchanged")
        whole.edit(.width, text: "758")
        try expect(whole.widthText == "758" && whole.heightText == "500" && whole.displayHeightText == "500", "proportional math on a whole-pixel size is unchanged")
        whole.edit(.height, text: "1000")
        try expect(whole.widthText == "1516" && (try whole.submission().size) == CGSize(width: 1516, height: 1000), "a typed 1000 round-trips to the original 1516 x 1000")
        // OSN-058 round 2: the panel must never reject a value it displays. Apply and OK both take the shown whole pixels.
        let shown = CGSize(width: 1516.5, height: 1010.7)
        var untouchedState = ResizePanelState(size: shown)
        try expect(untouchedState.displayWidthText == "1517" && untouchedState.displayHeightText == "1011", "fractional source displays 1517 x 1011")
        try expect(try untouchedState.submission().size == CGSize(width: 1517, height: 1011), "untouched fields submit the displayed 1517 x 1011")
        for viaOK in [false, true] {
            var previewed: [CGSize] = []
            var committed: [CGSize] = []
            let fractionalSession = ResizePanelSession(size: shown, onPreview: { previewed.append($0.size) }, onFinish: { _ in })
            fractionalSession.onCompletion = { _ in }
            if viaOK {
                try expect(try fractionalSession.apply(), "OK on an untouched fractional source succeeds")
                try expect(fractionalSession.isFinished && previewed == [CGSize(width: 1517, height: 1011)], "OK previews then commits the displayed 1517 x 1011")
            } else {
                try expect(try fractionalSession.preview(), "Apply on an untouched fractional source succeeds")
                try expect(!fractionalSession.isFinished && previewed == [CGSize(width: 1517, height: 1011)], "Apply previews the displayed 1517 x 1011")
                fractionalSession.cancel()
            }
            let delivering = ResizePanelSession(size: shown) { size, _, _ in committed.append(size) }
            try expect(try delivering.apply(), "OK delivers for an untouched fractional source")
            try expect(committed == [CGSize(width: 1517, height: 1011)], "OK callback receives 1517 x 1011, got \(committed)")
        }
        // typed values behave exactly as before: whole text is honoured, fractional or non-numeric text is still rejected
        untouchedState.setPreserveRatio(false)
        untouchedState.edit(.width, text: "1516")
        try expect(try untouchedState.submission().size == CGSize(width: 1516, height: 1011), "typed 1516 stays 1516; the untouched partner submits its displayed 1011")
        for bad in ["12.5", "abc", "1516.5"] {
            var badState = ResizePanelState(size: shown)
            badState.edit(.width, text: bad)
            try rejects { _ = try badState.submission() }
            var badHeight = ResizePanelState(size: shown)
            badHeight.edit(.height, text: bad)
            try rejects { _ = try badHeight.submission() }
        }
        // proportional lock: a fractional source has no usable ratio (validate rejects it), so the lock is off and the
        // untouched partner's rounded display is the value that submits. On a whole-pixel source the lock is live and the
        // partner is recomputed from the exact original ratio, so an untouched partner never feeds the math.
        var locked = ResizePanelState(size: shown)
        locked.setPreserveRatio(true)
        try expect(!locked.locksProportions, "fractional source cannot lock proportions")
        locked.edit(.width, text: "758")
        try expect(locked.heightText == "1010.7" && (try locked.submission().size) == CGSize(width: 758, height: 1011), "fractional source: width edit leaves the partner untouched and it submits 1011")
        var wholeLock = ResizePanelState(size: CGSize(width: 1516, height: 1010))
        try expect(wholeLock.locksProportions, "whole source locks")
        wholeLock.edit(.width, text: "758")
        try expect(wholeLock.heightText == "505" && (try wholeLock.submission().size) == CGSize(width: 758, height: 505), "whole source: lock math unchanged")
        wholeLock.edit(.height, text: "202")
        try expect(wholeLock.widthText == "303" && (try wholeLock.submission().size) == CGSize(width: 303, height: 202), "height drives width from the exact ratio")
        // unlocked: editing one field leaves the other untouched, and it submits its rounded display
        var unlockedPartner = ResizePanelState(size: shown)
        unlockedPartner.setPreserveRatio(false)
        unlockedPartner.edit(.height, text: "400")
        try expect(try unlockedPartner.submission().size == CGSize(width: 1517, height: 400), "untouched width submits its displayed 1517")
        // limit mode: an untouched fractional limit field submits its displayed whole pixels too
        var limitFractional = ResizePanelState(size: shown)
        limitFractional.setMode(.limit)
        try expect(limitFractional.displayLimitText == "1517", "limit field shows 1517")
        try expect(try limitFractional.submission().size == CGSize(width: 1517, height: 1011), "untouched limit submits the displayed 1517 without erroring, got \(try limitFractional.submission().size)")
        limitFractional.limitText = "12.5"
        try rejects { _ = try limitFractional.submission() }
        print("ResizePanelTests: \(checks) checks passed (pure state; no desktop input)")
    }
}
#endif
