import AppKit

/// What History asks of the app: where its questions appear, and how an upload's deletion binding is kept.
extension AppDelegate {
    /// The window a History question belongs to: History itself while it is on screen, else the editor.
    var historyHost: NSWindow {
        if let history = historyWindow, history.isVisible, !history.isMiniaturized { return history }
        return window
    }

    /// Raises an alert as a sheet on History, so a click there is answered there and History is never left waiting on a sheet it cannot show.
    func presentFromHistory(_ alert: AppAlert, completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        present(alert, on: historyHost, completion: completion)
    }

    /// The binding an upload keeps for Delete from Web: the one captured before the transfer, kept only while capturing again for the
    /// published URL gives the same four stable fields (format, destination digest, SSH digest, public URL). Anything else, a failed
    /// capture included, keeps none, and the History icon says why instead of deleting from a destination nobody can vouch for.
    static func retainedBinding(planned: [String: String]?, published: [String: String]?) -> [String: String]? {
        guard let planned, let published else { return nil }
        let stable = ["version", "destinationSHA256", "sshConfigSHA256", "publicURL"]
        return stable.allSatisfy({ planned[$0] == published[$0] }) ? planned : nil
    }
}
