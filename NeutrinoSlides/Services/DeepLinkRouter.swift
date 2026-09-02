import Foundation
import os.log
import NeutrinoCore

// MARK: - DeepLinkRouter

/// Holds the presentation an inbound Universal Link asked for until the app is in a state to open
/// it.
///
/// `https://www.getneutrino.app/open/slide/<file id>` is how Drive (or an email, or the web app)
/// hands a deck to this app. Only the id travels; the deck itself is fetched from the server here,
/// so the reader always gets the current version and permissions stay server-side.
///
/// A link can land at any moment — including a cold launch straight onto the login screen, or while
/// the biometric lock overlay is up. Rather than teach the open path about those states, the router
/// just remembers the destination and the view layer picks it up once the user is signed in. That
/// is also why nothing but `consume()` clears `pending`: a link that arrives before sign-in has to
/// survive the whole login round trip.
///
/// > Note: `/open/slide/*` is routed to `com.neutrino.drive` by the currently deployed
/// > `apple-app-site-association`. Moving it to this bundle id is Epic 20, sequenced with the App
/// > Store release. Until then this router only ever sees links that arrive by paste or from
/// > another app — the code path is correct, it is simply not exercised by iOS yet.
@MainActor
final class DeepLinkRouter: ObservableObject {

    // MARK: - State

    /// The presentation waiting to be opened, if any.
    @Published private(set) var pending: NeutrinoAppLink.Destination?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NeutrinoSlides",
                                category: "DeepLinkRouter")

    // MARK: - Init

    init(pending: NeutrinoAppLink.Destination? = nil) {
        self.pending = pending
    }

    // MARK: - Inbound

    /// Records `url` if it is a Neutrino presentation link.
    ///
    /// Returns false for every other kind. A `/open/sheet/…` link belongs to Neutrino Sheets — the
    /// apps store entirely different formats, and opening one here would either fail to decode or,
    /// worse, silently show an empty deck where a spreadsheet's data should be.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let destination = NeutrinoAppLink.destination(from: url) else { return false }
        guard destination.kind == .slide else {
            logger.debug("ignoring app link for kind=\(destination.kind.rawValue, privacy: .public)")
            return false
        }
        logger.debug("accepted presentation link file=\(destination.fileID, privacy: .public)")
        pending = destination
        return true
    }

    /// Returns the pending destination and clears it, so a presentation that is already being
    /// opened is not opened a second time when the view tree re-evaluates.
    func consume() -> NeutrinoAppLink.Destination? {
        defer { pending = nil }
        return pending
    }

    func clear() {
        pending = nil
    }
}
