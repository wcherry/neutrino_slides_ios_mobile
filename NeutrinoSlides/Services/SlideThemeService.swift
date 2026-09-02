import Foundation
import os.log
import NeutrinoCore
import NeutrinoAuth

// MARK: - SlideThemeService

/// The account's saved themes, from `GET /api/v1/slides/themes`.
///
/// The one Slides endpoint that is not a Drive endpoint. A theme is a user-owned *record* rather
/// than a file — it has no content to encrypt and belongs to the account, not to a deck — so it
/// survived the drive refactor with its own resource.
///
/// Read-only here. Creating and editing themes is a web feature (Epic 21 on this side), and a
/// gallery that could only offer what the server already holds is still the whole point: applying a
/// theme to a deck is what a phone is for, and inventing one is not.
///
/// A failure is not surfaced as an error. ``SlideTheme/builtIns`` is always offered, so a themes
/// request that fails costs the user the themes they made on the web, not the ability to restyle a
/// deck — and it costs it silently, because a red banner over a gallery that is visibly working
/// would be noise.
@MainActor
final class SlideThemeService: ObservableObject {

    // MARK: - Published State

    /// The account's themes, most recently created last, as the server orders them.
    @Published private(set) var themes: [StoredSlideTheme] = []
    @Published private(set) var isLoading = false
    /// True once a load has completed, successfully or not, so the gallery can tell "still loading"
    /// from "there is nothing to show".
    @Published private(set) var hasLoaded = false

    // MARK: - Dependencies

    /// Set once at app launch so the service can refresh tokens before requests.
    weak var authService: AuthService?

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NeutrinoSlides",
                                category: "SlideThemeService")

    private let session: URLSession

    private var baseURL: String { AuthService.baseURL }

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Load

    /// Loads the account's themes. Safe to call from `.task` on every appearance of the gallery: a
    /// second call while one is in flight is dropped.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            await authService?.refreshTokenIfNeeded()
            guard let token = KeychainService.load(forKey: AuthService.accessTokenKey),
                  let url = URL(string: baseURL + "/api/v1/slides/themes") else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.error("load themes: unexpected response")
                return
            }
            themes = try JSONDecoder().decode(ThemeListResponse.self, from: data).themes
            logger.debug("loaded \(self.themes.count) theme(s)")
        } catch {
            // Deliberately not published — see the type's note.
            logger.error("load themes failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Gallery

    /// What the gallery shows: the built-in themes, then the account's, with any duplicate name
    /// from the server winning.
    ///
    /// Merged rather than replaced so the gallery is never empty and never *shrinks* when a request
    /// fails — a user who applied "Midnight" a minute ago should still find it there.
    var galleryThemes: [SlideTheme] {
        let stored = themes.map(\.asDeckTheme)
        let storedNames = Set(stored.map(\.name))
        return SlideTheme.builtIns.filter { !storedNames.contains($0.name) } + stored
    }
}

// MARK: - API Models

private struct ThemeListResponse: Decodable {
    let themes: [StoredSlideTheme]
}
