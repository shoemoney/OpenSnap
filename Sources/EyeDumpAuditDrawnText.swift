import AppKit

/// F-R-001: a capture must show what the layout JSON says. The window server can hand back the frame before a label's new text reached it
/// (19 of 21 status-notice captures showed the old status while the layout JSON read the new one), so a shot that depends on a label's text
/// first waits, bounded, until the label's pixels in the window server's own image match what the label itself draws for its string.
extension AuditRun {
    /// How well the captured pixels of a label match the label's own rendering of its string: the share of the captured ink that lies on
    /// the expected ink (precision) and the share of the expected ink that was captured (recall), both with a small tolerance for edges.
    struct DrawnTextMatch {
        var precision: Double, recall: Double
        static let required = 0.9
        var ok: Bool { precision >= Self.required && recall >= Self.required }
        var json: [String: Any] { ["precision": (precision * 1000).rounded() / 1000, "recall": (recall * 1000).rounded() / 1000, "required": Self.required] }
    }

    /// Compares the window server's image of `field` with the field drawn alone; nil when there is nothing to compare (empty, hidden, no image).
    func drawnTextMatch(_ field: NSTextField, in target: NSWindow) -> DrawnTextMatch? {
        guard !field.stringValue.isEmpty, !field.isHiddenOrHasHiddenAncestor, field.bounds.width > 1, field.bounds.height > 1,
              let reference = field.bitmapImageRepForCachingDisplay(in: field.bounds) else { return nil }
        field.cacheDisplay(in: field.bounds, to: reference)
        guard let (image, _) = grab([target]), target.frame.width > 0 else { return nil }
        let width = reference.pixelsWide, height = reference.pixelsHigh
        let scale = CGFloat(image.width) / target.frame.width
        let inWindow = field.convert(field.bounds, to: nil)
        let region = CGRect(x: inWindow.minX * scale, y: (target.frame.height - inWindow.maxY) * scale,
                            width: inWindow.width * scale, height: inWindow.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard width > 0, height > 0, !region.isEmpty, let crop = image.cropping(to: region),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let gray = context.data else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = gray.assumingMemoryBound(to: UInt8.self)
        let background = Array(UnsafeBufferPointer(start: pixels, count: width * height)).sorted()[width * height / 2]
        var captured = [Bool](repeating: false, count: width * height), expected = captured
        for y in 0..<height {
            for x in 0..<width {
                captured[y * width + x] = abs(Int(pixels[y * width + x]) - Int(background)) > 50
                // The bitmap is stored top row first, the same as the context's memory, so the two masks line up.
                expected[y * width + x] = (reference.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3
            }
        }
        // One pixel of tolerance: the same rasteriser drew both, so a right string matches exactly and a wrong one (measured 0.78 / 0.82 at two pixels) does not.
        let reach = 1
        func near(_ mask: [Bool], _ x: Int, _ y: Int) -> Bool {
            for dy in -reach...reach { for dx in -reach...reach {
                let nx = x + dx, ny = y + dy
                if nx >= 0, nx < width, ny >= 0, ny < height, mask[ny * width + nx] { return true }
            } }
            return false
        }
        var capturedInk = 0, capturedOnExpected = 0, expectedInk = 0, expectedCaptured = 0
        for y in 0..<height { for x in 0..<width {
            if captured[y * width + x] { capturedInk += 1; if near(expected, x, y) { capturedOnExpected += 1 } }
            if expected[y * width + x] { expectedInk += 1; if near(captured, x, y) { expectedCaptured += 1 } }
        } }
        guard expectedInk > 0 else { return nil }
        // Nothing captured at all is a total mismatch, not a pass.
        return DrawnTextMatch(precision: capturedInk == 0 ? 0 : Double(capturedOnExpected) / Double(capturedInk), recall: Double(expectedCaptured) / Double(expectedInk))
    }

    /// Forces the field's window to display and waits (at most `timeout`) until the window server shows the field's current string.
    /// Returns what was last measured, and whether it matched. The label's own cell text is read back first: it is what the next draw uses.
    func settleDrawnText(_ field: NSTextField, in target: NSWindow, timeout: TimeInterval = 4) -> (ok: Bool, match: DrawnTextMatch?, attempts: Int, text: String) {
        let text = field.stringValue
        guard field.cell?.attributedStringValue.string == text else { return (false, nil, 0, text) }
        var last: DrawnTextMatch?
        var attempts = 0
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            attempts += 1
            field.needsDisplay = true
            target.contentView?.layoutSubtreeIfNeeded(); target.displayIfNeeded()
            CATransaction.flush()
            pump(0.12)
            if field.stringValue != text { return (false, last, attempts, text) }
            last = drawnTextMatch(field, in: target)
            if last?.ok == true { return (true, last, attempts, text) }
        } while Date() < deadline
        return (false, last, attempts, text)
    }
}
