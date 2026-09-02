import Foundation
import CryptoKit
import XCTest
import NeutrinoCore
import NeutrinoAuth
import NeutrinoCrypto
@testable import NeutrinoSlides

// MARK: - TestKeys

/// Installs a real X25519 key pair into the Keychain so the encryption paths can be exercised for
/// what they actually are.
///
/// The crypto is deliberately *not* mocked. `crypto_box_seal` / `secretstream` round trips are the
/// part of this app most expensive to get subtly wrong, and a fake that always "decrypts" would
/// assert nothing about them. libsodium's `crypto_box` uses X25519 keys, which is exactly what
/// `Curve25519.KeyAgreement` produces, so a CryptoKit-generated pair is interchangeable with the
/// one the web app exports.
enum TestKeys {

    /// Generates a pair and stores it under the same Keychain keys the app reads.
    @discardableResult
    static func install() -> KeyBundle {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        let bundle = KeyBundle(
            publicKey: base64URL(priv.publicKey.rawRepresentation),
            privateKey: base64URL(priv.rawRepresentation),
            keyVersion: "1"
        )
        KeyImportService.storeKeys(bundle)
        return bundle
    }

    static func remove() {
        KeyImportService.removeKeys()
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - TestTokens

/// Puts an access token in the Keychain so services believe they are signed in.
enum TestTokens {

    /// Decodes to `{"alg":"none","typ":"JWT"}.{"sub":"test-user-id"}.` — a real (if unsigned) JWT
    /// shape, not just an opaque string, because `SlidesDriveService.currentUserId()` reads the
    /// `sub` claim to address the drive root (`GET /api/v1/drive/folders/{id}` with `id` the
    /// caller's own user id). `userId` below is that same "test-user-id" so a test that seeds a
    /// token can assert against it.
    static let userId = "test-user-id"
    static let defaultAccessToken =
        "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJ0ZXN0LXVzZXItaWQifQ."

    static func install(accessToken: String = TestTokens.defaultAccessToken) {
        KeychainService.save(accessToken, forKey: AuthService.accessTokenKey)
        // Far-future expiry so `refreshTokenIfNeeded` short-circuits and no test accidentally
        // depends on a refresh round trip it did not stub.
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        KeychainService.save(expiry, forKey: AuthService.tokenExpiryKey)
    }

    static func remove() {
        KeychainService.delete(forKey: AuthService.accessTokenKey)
        KeychainService.delete(forKey: AuthService.refreshTokenKey)
        KeychainService.delete(forKey: AuthService.tokenExpiryKey)
    }
}

// MARK: - TestServer

/// Points the app at a fixed host so assertions on request URLs are stable.
enum TestServer {
    static let host = "https://test.neutrino.local"

    static func use() {
        UserDefaults.standard.set(host, forKey: AuthService.serverHostKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: AuthService.serverHostKey)
    }
}

// MARK: - Fixtures

enum Fixture {

    // MARK: - Drive items

    /// A presentation item with sensible defaults, so a test only states what it cares about.
    static func deck(id: String = "deck-1",
                     name: String = "Kickoff",
                     parentID: String? = nil,
                     size: Int64? = 128,
                     modifiedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                     isTrashed: Bool = false,
                     isStarred: Bool = false,
                     isShared: Bool = false,
                     mimeType: String = SlideItem.slideMIME,
                     contentVersion: Int? = nil) -> SlideItem {
        SlideItem(id: id, name: name, type: .file, parentID: parentID, size: size,
                  modifiedAt: modifiedAt, isTrashed: isTrashed, mimeType: mimeType,
                  isStarred: isStarred, contentVersion: contentVersion, isShared: isShared)
    }

    static func folder(id: String = "folder-1",
                       name: String = "Projects",
                       parentID: String? = nil,
                       isStarred: Bool = false) -> SlideItem {
        SlideItem(id: id, name: name, type: .folder, parentID: parentID, size: nil,
                  modifiedAt: Date(timeIntervalSince1970: 1_700_000_000), isTrashed: false,
                  mimeType: nil, isStarred: isStarred)
    }

    // MARK: - Deck content

    static func textElement(id: String = "e1",
                            frame: SlideFrame = SlideFrame(x: 10, y: 10, w: 40, h: 20),
                            content: String = "Hello",
                            style: TextStyle = TextStyle(fontSize: 40, bold: true)) -> SlideElement {
        .text(TextElement(id: id, frame: frame, content: content, style: style))
    }

    static func shapeElement(id: String = "s1",
                             shape: String = "rect",
                             frame: SlideFrame = SlideFrame(x: 50, y: 50, w: 20, h: 20),
                             fill: String = "#818cf8") -> SlideElement {
        .shape(ShapeElement(id: id, shape: shape, frame: frame, fill: fill))
    }

    /// An element of a kind this app does not model — the case the preservation rules exist for.
    static func opaqueElement(id: String = "o1", kind: String = "sheetEmbed",
                              frame: SlideFrame = SlideFrame(x: 5, y: 5, w: 30, h: 30))
    -> SlideElement {
        .opaque(OpaqueElement([
            "id": .string(id),
            "type": .string(kind),
            "x": .number(frame.x), "y": .number(frame.y),
            "w": .number(frame.w), "h": .number(frame.h),
            "spreadsheetId": .string("sheet-9"),
            "cachedData": .string("[[1,2],[3,4]]"),
        ]))
    }

    static func slide(id: String = "sl1",
                      background: SlideBackground = .color("#ffffff"),
                      elements: [SlideElement] = [Fixture.textElement()],
                      notes: String = "",
                      transition: String = SlideTransition.fade.rawValue) -> Slide {
        Slide(id: id, background: background, elements: elements, notes: notes,
              transition: transition)
    }

    static func deckContent(slides: [Slide] = [Fixture.slide()],
                            theme: SlideTheme = .default,
                            master: SlideMaster? = .default) -> SlideDeck {
        SlideDeck(slides: slides, theme: theme, master: master)
    }

    /// The body the server seeds a brand-new presentation with — `EMPTY_SLIDES_CONTENT` in
    /// `src/drive/storage/native_types.rs`, byte for byte.
    static let seededDeckJSON = """
    {"slides":[{"id":"s1","background":{"type":"color","value":"#ffffff"},"elements":[\
    {"id":"e1","type":"text","x":10,"y":30,"w":80,"h":20,"content":"Click to add title",\
    "style":{"fontSize":40,"bold":true,"italic":false,"underline":false,"color":"#1f2937",\
    "align":"center","fontFamily":"Inter"}},{"id":"e2","type":"text","x":15,"y":55,"w":70,"h":15,\
    "content":"Click to add subtitle","style":{"fontSize":24,"bold":false,"italic":false,\
    "underline":false,"color":"#6b7280","align":"center","fontFamily":"Inter"}}],"notes":"",\
    "transition":"fade"}],"theme":{"name":"default","primaryColor":"#4f46e5",\
    "backgroundColor":"#ffffff","textColor":"#1f2937","accentColor":"#818cf8",\
    "fontFamily":"Inter","defaultTransition":"fade"}}
    """

    // MARK: - Drive JSON

    /// Drive's zone-less timestamp shape, as the file endpoints emit it.
    static func driveTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// A `GET /api/v1/drive` style listing body.
    static func listing(files: [String] = [], folders: [String] = []) -> Data {
        Data("""
        {"files":[\(files.joined(separator: ","))],"folders":[\(folders.joined(separator: ","))]}
        """.utf8)
    }

    static func fileJSON(id: String = "deck-1",
                         name: String = "Kickoff",
                         folderId: String? = nil,
                         sizeBytes: Int = 128,
                         mimeType: String = SlideItem.slideMIME,
                         updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                         isStarred: Bool = false,
                         contentVersion: Int? = nil) -> String {
        let folder = folderId.map { "\"\($0)\"" } ?? "null"
        let version = contentVersion.map { ",\"contentVersion\":\($0)" } ?? ""
        return """
        {"id":"\(id)","name":"\(name)","folderId":\(folder),"sizeBytes":\(sizeBytes),
         "mimeType":"\(mimeType)","updatedAt":"\(driveTimestamp(updatedAt))","isStarred":\(isStarred)\(version)}
        """
    }

    static func folderJSON(id: String = "folder-1",
                           name: String = "Projects",
                           parentId: String? = nil,
                           updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                           isStarred: Bool = false) -> String {
        let parent = parentId.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","name":"\(name)","parentId":\(parent),
         "updatedAt":"\(driveTimestamp(updatedAt))","isStarred":\(isStarred)}
        """
    }
}

// MARK: - Temp directories

extension XCTestCase {

    /// A unique empty directory, removed when the test finishes.
    func makeTemporaryDirectory(file: StaticString = #filePath, line: UInt = #line) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NeutrinoSlidesTests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            XCTFail("Could not create temp directory: \(error)", file: file, line: line)
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

// MARK: - JSON helpers

extension XCTestCase {

    /// A stored deck body as a dictionary, for asserting on what a save actually wrote.
    func jsonObject(_ data: Data, file: StaticString = #filePath, line: UInt = #line)
    -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("not a JSON object", file: file, line: line)
            return [:]
        }
        return object
    }
}
