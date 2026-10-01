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

    /// What a Neutrino presentation is: a real PowerPoint deck.
    ///
    /// A presentation created by any Neutrino client is a `.pptx` (`src/drive/storage/native_types.rs`,
    /// issue #127), which this app reads and writes through ``PptxCodec`` — so PowerPoint, Keynote
    /// and LibreOffice open one directly, and import and export are file copies. It is also exactly
    /// what the server's `type=slide` filter matches.
    ///
    /// The bespoke `application/x-neutrino-slide` JSON that predates it is gone from this app, as it
    /// is from the server and the web. Not migrated — no file was ever stored in it — simply no longer
    /// a format this app reads, writes, lists or routes.
    static let slideMIME = PptxCodec.mimeType

    /// Whether a Drive file is a Neutrino presentation.
    static func isPresentation(_ mimeType: String?) -> Bool {
        mimeType == slideMIME
    }

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
    /// ``slideMIME`` for presentations; `nil` for folders.
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
        type == .folder ? "folder.fill" : "rectangle.on.rectangle.angled.fill"
    }

    /// True when this file is a Neutrino presentation.
    ///
    /// This is the client-side check the drive refactor made necessary: `/info` answers for *any*
    /// file type now, so nothing server-side will tell the app it opened the wrong thing.
    var isNativeDeck: Bool {
        type == .file && Self.isPresentation(mimeType)
    }

    /// The title to show.
    ///
    /// A `.pptx` is a real deck and its extension is part of the *file* name — it has to land on
    /// disk as `Kickoff.pptx` to open on a double-click — but the presentation is called "Kickoff",
    /// which is what the web library shows too (`stripOoxmlExtension` in `web/packages/api-core`).
    var displayName: String {
        type == .file ? PptxCodec.strippingExtension(name) : name
    }

    /// The name a "Duplicate" should get: `Kickoff.pptx` -> `Kickoff copy.pptx`.
    ///
    /// The extension stays last, because `Kickoff.pptx copy` is a file the operating system no longer
    /// recognises.
    var duplicateName: String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return name + " copy"
        }
        return name[..<dot] + " copy" + name[dot...]
    }
}
