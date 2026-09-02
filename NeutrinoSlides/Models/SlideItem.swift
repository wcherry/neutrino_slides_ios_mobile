import Foundation

// MARK: - SlideItem

/// A single folder or presentation within the user's Neutrino Drive.
struct SlideItem: Identifiable, Hashable {

    // MARK: - ItemType

    enum ItemType {
        case folder
        case file
    }

    // MARK: - MIME

    /// The MIME type that *makes* a Drive file a presentation.
    ///
    /// There is no `slides` marker table and no `/api/v1/slides` CRUD resource for decks:
    /// membership in the server's `native_types` registry is the marker, and this string is the key
    /// into it (`src/drive/storage/native_types.rs`). It is also what the server's `type=slide`
    /// filter matches, and what the client-side "is this a presentation?" check in
    /// ``SlideContentService/fileInfo(for:)`` compares against. (`/api/v1/slides/themes` does still
    /// exist — a theme is a user-owned record rather than a file.)
    static let slideMIME = "application/x-neutrino-slide"

    /// A real `.pptx`, which the web app writes for decks created after issue #127 and which this
    /// app cannot open yet — office mode is Epic 22. Recognised so a listing can show the file and
    /// say why it will not open, rather than dropping it or failing obscurely.
    static let pptxMIME = "application/vnd.openxmlformats-officedocument.presentationml.presentation"

    // MARK: - Properties

    let id: String
    var name: String
    let type: ItemType
    /// `nil` means the root of the drive.
    var parentID: String?
    /// Bytes; `nil` for folders.
    var size: Int64?
    var modifiedAt: Date
    var isTrashed: Bool
    /// ``slideMIME`` for native presentations; `nil` for folders.
    var mimeType: String?
    /// Drive's `isStarred` flag — the Favorites model shared with the web app, stored on the file or
    /// folder row itself rather than in a list of its own.
    var isStarred: Bool = false
    /// Drive's `contentVersion` as of the last time this device heard from the server. Sent back as
    /// `expectedContentVersion` on the next save so the server can reject a stale write; nil means
    /// unguarded.
    var contentVersion: Int?
    /// True for items reached through `GET /drive/shared-with-me`, i.e. owned by somebody else.
    var isShared: Bool = false

    // MARK: - Computed

    /// SF Symbol representing the item in a listing.
    var iconName: String {
        switch type {
        case .folder: return "folder.fill"
        case .file:   return isNativeDeck ? "rectangle.on.rectangle.angled.fill" : "doc.fill"
        }
    }

    /// True when this file is a native Neutrino presentation rather than a raw office file.
    ///
    /// This is the client-side check the drive refactor made necessary: `/info` answers for *any*
    /// file type now, so nothing server-side will tell the app it opened the wrong thing.
    var isNativeDeck: Bool {
        type == .file && mimeType == Self.slideMIME
    }

    /// A deck this app can list but not yet open — a real `.pptx`. Office mode (Epic 22) is what
    /// turns this into something openable.
    var isOfficeDeck: Bool {
        type == .file && mimeType == Self.pptxMIME
    }

    /// The title to show. A native deck is stored under its plain name, so only a `.pptx` has an
    /// extension worth hiding — which is exactly what the web app's `stripOoxmlExtension` does.
    var displayName: String {
        guard type == .file, isOfficeDeck else { return name }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// The name a "Duplicate" should get: `Kickoff` -> `Kickoff copy`,
    /// `Kickoff.pptx` -> `Kickoff copy.pptx`.
    var duplicateName: String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return name + " copy"
        }
        return name[..<dot] + " copy" + name[dot...]
    }
}
