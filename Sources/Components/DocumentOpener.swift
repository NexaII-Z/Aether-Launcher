import UIKit

/// Presents the system "Open in..." menu for a file. Minecraft appears in it because the
/// official app declares .mcpack/.mcworld/.mctemplate/.mcaddon as document types.
@MainActor
enum DocumentOpener {
    private static var controller: UIDocumentInteractionController?

    @discardableResult
    static func presentOpenInMenu(for url: URL) -> Bool {
        guard let host = topViewController() else { return false }
        let interaction = UIDocumentInteractionController(url: url)
        controller = interaction
        let anchor = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
        return interaction.presentOpenInMenu(from: anchor, in: host.view, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
