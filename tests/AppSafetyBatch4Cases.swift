// Audit fix batch 4: the App-side findings of the E2E journeys J2 and J3 (docs/design/e2e/findings.md).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen and nothing touches the network.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var batch4Cases: [(String, () throws -> Void)] {
        [
            ("A fitted screenshot is stored, titled, archived and resized in whole pixels, never a fraction of the fit scale (F-J3-006)", b4WholePixelSizes)
        ]
    }

    // MARK: Sizes

    private static func b4WholePixelSizes() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let source = CGSize(width: 6001, height: 3999)
        app.canvas.newBlank(size: source)
        app.canvas.setBackground(try image(size: source))
        app.documentGeneration = UUID(); app.canvas.editingUndoManager.removeAllActions()
        app.adoptRasterViewport()
        let output = app.canvas.outputSize, capacity = try app.maximumNormalCanvas.b4Unwrap("the fit capacity")
        try expect(output.width < source.width && capacity.width < source.width, "The fixture needs a source larger than the screen (\(output), \(capacity))")
        func whole(_ size: CGSize) -> Bool { size.width == size.width.rounded() && size.height == size.height.rounded() }
        try expect(whole(output), "The fitted output is whole pixels (\(output.width) × \(output.height))")
        let exact = CGSize(width: source.width * min(capacity.width / source.width, capacity.height / source.height),
                           height: source.height * min(capacity.width / source.width, capacity.height / source.height))
        try expect(abs(output.width - exact.width) <= 0.5 && abs(output.height - exact.height) <= 0.5, "Rounded to the nearest pixel (\(output) vs \(exact))")
        // The size the editor titles, the History entry records and the Resize sheet opens with all agree on integers.
        app.updateDragPreview()
        let label = app.dragSizeLabel.stringValue
        let shown = app.dragAtOriginalSize ? source : output
        try expect(label.hasPrefix("\(Int(shown.width)) × \(Int(shown.height)) · "), "The status and title read whole pixels (\(label))")
        let snapshot = try app.historySnapshot()
        try expect(whole(snapshot.size) && snapshot.size == output, "The History entry records the whole output size (\(snapshot.size))")
        let session = try app.makeResizeSession().b4Unwrap("the resize session")
        try expect(session.state.widthText == String(Int(output.width)) && session.state.heightText == String(Int(output.height)),
                   "The Resize sheet opens on the whole output size (\(session.state.widthText) × \(session.state.heightText))")
        session.cancel()
        _ = store
    }
}

extension Optional {
    func b4Unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing \(what)") }
        return self
    }
}
#endif
