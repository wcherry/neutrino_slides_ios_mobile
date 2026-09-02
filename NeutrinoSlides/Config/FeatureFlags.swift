// MARK: - FeatureFlags

/// Compile-time switches for the Phase 1 feature set (see `agent_docs/road_map.md`).
///
/// Every flag for a shipped epic defaults to `true`. They exist so a feature can be switched off in
/// a build without unpicking its wiring, which is how the sibling Neutrino apps shipped their
/// epics. Flags for epics that have not been written yet are absent rather than `false` — a flag
/// guarding code that does not exist reads as though the feature is one toggle away.
enum FeatureFlags {

    // MARK: - Phase 1

    /// Epic 3 — Drive integration: browsing Home / Recent / Favorites / Shared / Trash, folder
    /// navigation, and the create / rename / delete / move / duplicate / star operations.
    static let driveIntegration: Bool = true

    /// Epic 2 — importing the encryption key by scanning the PIN-protected QR code the web app
    /// shows, alongside the key-file and vault-password paths. Requires `NSCameraUsageDescription`.
    static let qrKeyScan: Bool = true

    /// Epic 2 / Epic 24 — Face ID / Touch ID unlock for the app and for encryption-key access.
    static let biometricLock: Bool = true

    /// Epic 5 — the read-only deck: the 16:9 canvas, the thumbnail rail, text and shape elements,
    /// backgrounds and speaker notes.
    static let canvas: Bool = true

    /// Epic 6 / Epic 7 — editing a deck: moving and resizing elements, editing text, adding text
    /// boxes and shapes, and saving back to Drive.
    ///
    /// Switching this off leaves a viewer, which is a genuinely useful build: every element carries
    /// its own position and style, so a deck renders correctly without anything here being able to
    /// change it.
    static let deckEditing: Bool = true

    /// Epic 8 — slide management: add, duplicate, delete, reorder, and the layout gallery.
    ///
    /// Switching this off leaves Epic 7's editor — elements on the slides that already exist can
    /// still be edited — because nothing here changes how a deck is read. Like the flags below it
    /// does not switch editing *on*: every command behind it goes through the same `isEditable`
    /// guard a text edit does.
    static let slideManagement: Bool = true

    // MARK: - Phase 2

    /// Epic 10 — theming: the theme gallery, per-slide backgrounds and transitions, and the slide
    /// master's title/body styles.
    static let theming: Bool = true

    /// Epic 12 — presenter mode: full-screen playback, the transitions, and the speaker-notes
    /// view.
    static let presenting: Bool = true

    /// Epic 20 — accepting inbound `https://www.getneutrino.app/open/slide/<id>` Universal Links.
    ///
    /// Off, and deliberately: the deployed `apple-app-site-association` still routes
    /// `/open/slide/*` to `com.neutrino.drive`, so iOS does not hand those links to this app. The
    /// router and the entitlement are in place, so turning this on is one line — but it has to be
    /// sequenced with the AASA change in the server repo *and* the App Store release, or links
    /// break for users who have Drive installed and this app not.
    static let appLinks: Bool = false
}
