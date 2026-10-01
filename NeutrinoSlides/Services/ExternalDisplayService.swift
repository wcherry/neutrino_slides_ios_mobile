import SwiftUI
import UIKit

// MARK: - ExternalDisplayService

/// Presenting on a second screen — an AirPlay receiver, a USB-C or Lightning adapter, a Sidecar
/// display.
///
/// iOS hands an external display to the app as a scene of its own, with the
/// `windowExternalDisplayNonInteractive` role. Left unclaimed, the system mirrors the phone, which
/// puts the presenter's chrome, notes and thumb on the projector. Claimed, the room sees only the
/// slide and the phone is free to be a presenter console: current slide, next slide, notes, clock.
///
/// The one exception to "nothing reaches for a singleton" in this app: the scene delegate that owns
/// the external window is instantiated by UIKit, not by ``NeutrinoSlidesApp``, so there is no
/// initializer to inject through. The app injects this same instance into the view tree, so every
/// SwiftUI caller still receives it as an environment object.
@MainActor
final class ExternalDisplayService: ObservableObject {

    static let shared = ExternalDisplayService()

    // MARK: - Published state

    /// Whether an external display scene is connected and showing this app's window.
    @Published private(set) var isConnected = false

    /// The deck on the external display, or `nil` when nothing is being presented — the display
    /// then shows a holding screen rather than the editor.
    @Published private(set) var deck: SlideDeck?
    /// The slide on the external display.
    @Published private(set) var index = 0
    /// Which way the last move went, so the external display plays a directional transition the
    /// same way round as the phone.
    @Published private(set) var isAdvancing = true
    /// Changes with every ``begin(deck:at:)``, so the external view rebuilds for a new
    /// presentation rather than animating from the last slide of the previous one.
    @Published private(set) var sessionID = UUID()

    init() {}

    // MARK: - Connection

    /// Called by ``ExternalDisplaySceneDelegate``.
    func displayDidConnect() {
        isConnected = true
    }

    /// Called by ``ExternalDisplaySceneDelegate``.
    func displayDidDisconnect() {
        isConnected = false
    }

    // MARK: - Presentation

    /// Starts sending a deck to the external display.
    ///
    /// Safe to call with no display connected: the state is kept, so a display plugged in
    /// mid-presentation picks up at the current slide.
    func begin(deck: SlideDeck, at index: Int) {
        self.deck = deck
        self.index = deck.slides.indices.contains(index) ? index : 0
        self.isAdvancing = true
        self.sessionID = UUID()
    }

    /// Moves the external display to a slide. Ignored outside a presentation.
    func show(index target: Int) {
        guard let deck, deck.slides.indices.contains(target), target != index else { return }
        isAdvancing = target > index
        index = target
    }

    /// Stops presenting; the external display goes back to its holding screen.
    func end() {
        deck = nil
        index = 0
        isAdvancing = true
    }
}

// MARK: - ExternalDisplaySceneDelegate

/// Owns the window on an external display.
///
/// Named by ``SlidesAppDelegate`` for scenes with the external-display role only; the app's own
/// scene stays with SwiftUI's `WindowGroup`.
@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let service = ExternalDisplayService.shared
        let host = UIHostingController(rootView: ExternalDisplayView().environmentObject(service))
        host.view.backgroundColor = .black

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.isHidden = false
        self.window = window

        service.displayDidConnect()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        ExternalDisplayService.shared.displayDidDisconnect()
    }
}

// MARK: - SlidesAppDelegate

/// Routes the external-display scene to ``ExternalDisplaySceneDelegate``, and answers the
/// orientation question for ``OrientationLock``.
///
/// Every other role gets a plain configuration, which SwiftUI fills in with its own delegate — so
/// the `WindowGroup` in ``NeutrinoSlidesApp`` behaves exactly as it did without this.
@MainActor
final class SlidesAppDelegate: NSObject, UIApplicationDelegate {

    /// Once implemented, this replaces the Info.plist orientation list rather than narrowing it,
    /// so the unlocked value has to restate it.
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.current
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        guard role == .windowExternalDisplayNonInteractive else {
            return UISceneConfiguration(name: nil, sessionRole: role)
        }
        // Named after the Info.plist entry in project.yml, which is what makes iOS offer this
        // scene at all rather than mirroring.
        let configuration = UISceneConfiguration(name: "External Display", sessionRole: role)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        return configuration
    }
}

// MARK: - OrientationLock

/// Holds the phone in one orientation while the presenter console is up.
///
/// With the deck on an external display the phone is a notes reader in the presenter's hand, and
/// portrait gives the notes the most room. Left free, the phone would turn to landscape every time
/// it is tilted toward the room.
@MainActor
enum OrientationLock {

    /// What Info.plist declares, per idiom.
    static var unlocked: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    private(set) static var current: UIInterfaceOrientationMask = unlocked

    static func lock(_ mask: UIInterfaceOrientationMask) {
        apply(mask)
    }

    static func unlock() {
        apply(unlocked)
    }

    private static func apply(_ mask: UIInterfaceOrientationMask) {
        guard mask != current else { return }
        current = mask
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        for scene in scenes {
            // Every controller in the presentation chain: the presenter is a full-screen cover,
            // and it is the topmost one whose answer UIKit asks for.
            var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
