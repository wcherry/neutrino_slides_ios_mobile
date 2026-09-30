import XCTest
import Sodium
@testable import NeutrinoSlides

/// The encrypted body: the round trip, the key handling, and the three checks the server no longer
/// does for us.
@MainActor
final class SlideContentServiceTests: XCTestCase {

    private var service: SlideContentService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        TestServer.use()
        TestKeys.install()
        TestTokens.install()
        service = SlideContentService(session: MockURLProtocol.makeSession())
    }

    override func tearDown() {
        MockURLProtocol.reset()
        TestKeys.remove()
        TestTokens.remove()
        TestServer.reset()
        super.tearDown()
    }

    // MARK: - Crypto

    func testEncryptAndDecryptRoundTrip() throws {
        let dek = Sodium().secretStream.xchacha20poly1305.key()
        let text = Fixture.seededDeckJSON

        let ciphertext = try service.encrypt(text: text, dek: dek,
                                             xcss: Sodium().secretStream.xchacha20poly1305)
        let plaintext = try service.decrypt(data: ciphertext, dek: dek)

        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), text)
        XCTAssertNotEqual(ciphertext, Data(text.utf8))
    }

    func testCiphertextCarriesTheSecretstreamHeader() throws {
        let dek = Sodium().secretStream.xchacha20poly1305.key()

        let ciphertext = try service.encrypt(text: "x", dek: dek,
                                             xcss: Sodium().secretStream.xchacha20poly1305)

        // 24-byte header plus the sealed message; the web client reads it the same way.
        XCTAssertGreaterThan(ciphertext.count, 24)
    }

    func testDecryptingWithTheWrongKeyFails() throws {
        let dek = Sodium().secretStream.xchacha20poly1305.key()
        let other = Sodium().secretStream.xchacha20poly1305.key()
        let ciphertext = try service.encrypt(text: "secret", dek: dek,
                                             xcss: Sodium().secretStream.xchacha20poly1305)

        XCTAssertThrowsError(try service.decrypt(data: ciphertext, dek: other))
    }

    func testTruncatedContentIsRefusedRatherThanRead() {
        let dek = Sodium().secretStream.xchacha20poly1305.key()

        XCTAssertThrowsError(try service.decrypt(data: Data([1, 2, 3]), dek: dek))
    }

    func testSealAndUnsealTheFileKey() throws {
        let dek = Sodium().secretStream.xchacha20poly1305.key()

        let sealed = try service.sealDEK(dek)
        let opened = try service.unsealDEK(sealed.sealed, keyVersion: sealed.keyVersion)

        XCTAssertEqual(opened, dek)
        XCTAssertEqual(sealed.keyVersion, 1)
    }

    func testAKeyVersionThisDeviceLacksIsReportedAsSuchRatherThanAsCorruption() throws {
        // Sealed to a key this device does not hold. Sealing to the device's own key and naming v7
        // would now open — a ref naming the wrong version is repaired, not refused.
        let dek = Sodium().secretStream.xchacha20poly1305.key()
        let absentKey = Sodium().box.keyPair()!
        let sealed = Sodium().utils.bin2base64(
            Sodium().box.seal(message: dek, recipientPublicKey: absentKey.publicKey)!,
            variant: .URLSAFE_NO_PADDING)!

        XCTAssertThrowsError(try service.unsealDEK(sealed, keyVersion: 7)) { error in
            guard case SlideContentError.missingKeyVersion(let version) = error else {
                return XCTFail("expected missingKeyVersion, got \(error)")
            }
            XCTAssertEqual(version, 7)
        }
    }

    func testARefNamingTheWrongVersionStillOpens() throws {
        // What the vault unlock produced on a rotated account: sealed to the key this device holds,
        // recorded under a version that is not that key's.
        let dek = Sodium().secretStream.xchacha20poly1305.key()
        let sealed = try service.sealDEK(dek)

        XCTAssertEqual(try service.unsealDEK(sealed.sealed, keyVersion: 7), dek)
    }

    func testWithNoKeyAtAllSealingSaysSoPlainly() {
        TestKeys.remove()
        let dek = Sodium().secretStream.xchacha20poly1305.key()

        XCTAssertThrowsError(try service.sealDEK(dek)) { error in
            guard case SlideContentError.noEncryptionKey = error else {
                return XCTFail("expected noEncryptionKey, got \(error)")
            }
        }
    }

    // MARK: - File info

    func testFileInfoDecidesWhetherAFileIsAPresentation() async throws {
        MockURLProtocol.respond(json: """
        {"id":"d1","name":"Kickoff","sizeBytes":10,"folderId":null,
         "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00",
         "yourRole":"editor","contentVersion":3}
        """)

        let info = try await service.fileInfo(for: "d1")

        XCTAssertEqual(info?.isNativeDeck, true)
        XCTAssertEqual(info?.isEditable, true)
        XCTAssertEqual(info?.contentVersion, 3)
        XCTAssertEqual(info?.isLive, true)
    }

    func testAPptxIsNotANativePresentation() async throws {
        MockURLProtocol.respond(json: """
        {"id":"d1","name":"Kickoff.pptx","sizeBytes":10,"folderId":null,
         "mimeType":"\(SlideItem.pptxMIME)","updatedAt":"2026-08-10T12:00:00","yourRole":"owner"}
        """)

        let info = try await service.fileInfo(for: "d1")

        XCTAssertEqual(info?.isNativeDeck, false)
    }

    func testAFileThatIsGoneOrNotSharedReadsAsNothingRatherThanAnError() async throws {
        MockURLProtocol.respond(json: "{}", statusCode: 404)
        let missing = try await service.fileInfo(for: "d1")
        XCTAssertNil(missing)

        MockURLProtocol.respond(json: "{}", statusCode: 403)
        let forbidden = try await service.fileInfo(for: "d1")
        XCTAssertNil(forbidden)
    }

    func testATrashedFileIsDescribedButNotLive() async throws {
        MockURLProtocol.respond(json: """
        {"id":"d1","name":"Kickoff","sizeBytes":10,"folderId":null,
         "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00",
         "deletedAt":"2026-08-11T09:00:00","yourRole":"owner"}
        """)

        let info = try await service.fileInfo(for: "d1")

        XCTAssertEqual(info?.isLive, false)
    }

    func testZonelessTimestampsAreReadAsUTC() async throws {
        MockURLProtocol.respond(json: """
        {"id":"d1","name":"Kickoff","sizeBytes":10,"folderId":null,
         "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00","yourRole":"owner"}
        """)

        let info = try await service.fileInfo(for: "d1")

        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 10
        components.hour = 12; components.minute = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(info?.updatedAt, calendar.date(from: components))
    }

    // MARK: - Create

    func testCreatingAPresentationStoresItsKeyAndReturnsTheServersIdentity() async throws {
        MockURLProtocol.handler = { request in
            let ok = { (data: Data) in
                (HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!, data)
            }
            if request.url?.path.hasSuffix("/key") == true { return ok(Data("{}".utf8)) }
            return ok(Data("""
            {"id":"new-1","name":"Kickoff","folderId":"f1","sizeBytes":0,
             "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00",
             "contentVersion":1}
            """.utf8))
        }

        let item = try await service.createPresentation(name: "Kickoff", parentID: "f1")

        XCTAssertEqual(item.id, "new-1")
        XCTAssertEqual(item.parentID, "f1")
        XCTAssertTrue(item.isNativeDeck)
        XCTAssertEqual(item.contentVersion, 1)

        let keyRequest = MockURLProtocol.request { $0.url?.path.hasSuffix("/key") == true }
        XCTAssertEqual(keyRequest?.httpMethod, "PUT")
    }

    func testTheCreateRequestNamesTheFileAndItsMimeType() async throws {
        MockURLProtocol.handler = { request in
            let ok = { (data: Data) in
                (HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!, data)
            }
            if request.url?.path.hasSuffix("/key") == true { return ok(Data("{}".utf8)) }
            return ok(Data("""
            {"id":"new-1","name":"Kickoff","folderId":null,"sizeBytes":0,
             "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00"}
            """.utf8))
        }

        _ = try await service.createPresentation(name: "Kickoff", parentID: nil)

        let body = jsonObject(MockURLProtocol.bodies[0])
        XCTAssertEqual(body["name"] as? String, "Kickoff")
        XCTAssertEqual(body["mimeType"] as? String, SlideItem.slideMIME)
        XCTAssertNotNil(body["id"], "the id is client-supplied so the editor can open it at once")
    }

    // MARK: - Load

    func testLoadingDecryptsAndDecodesTheDeck() async throws {
        let dek = Sodium().secretStream.xchacha20poly1305.key()
        let sealed = try service.sealDEK(dek)
        let ciphertext = try service.encrypt(text: Fixture.seededDeckJSON, dek: dek,
                                             xcss: Sodium().secretStream.xchacha20poly1305)
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let ok = { (data: Data) in
                (HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!, data)
            }
            if path.hasSuffix("/info") {
                return ok(Data("""
                {"id":"d1","name":"Kickoff","sizeBytes":10,"folderId":null,
                 "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00",
                 "yourRole":"owner","contentVersion":2}
                """.utf8))
            }
            if path.hasSuffix("/key") {
                return ok(Data("""
                {"encrypted_file_key":"\(sealed.sealed)","key_version":1}
                """.utf8))
            }
            return ok(ciphertext)
        }

        let loaded = try await service.loadDeck(for: "d1")

        XCTAssertEqual(loaded.file.slides.count, 1)
        XCTAssertEqual(loaded.info.contentVersion, 2)
        XCTAssertFalse(loaded.needsInitialEncryption)
        XCTAssertEqual(loaded.dek, dek)
    }

    func testContentThatWillNotDecryptWithAnExistingKeyIsNeverReadAsPlaintext() async throws {
        let sealed = try service.sealDEK(Sodium().secretStream.xchacha20poly1305.key())
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let ok = { (data: Data) in
                (HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!, data)
            }
            if path.hasSuffix("/info") {
                return ok(Data("""
                {"id":"d1","name":"Kickoff","sizeBytes":10,"folderId":null,
                 "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00",
                 "yourRole":"owner"}
                """.utf8))
            }
            if path.hasSuffix("/key") {
                return ok(Data("{\"encrypted_file_key\":\"\(sealed.sealed)\",\"key_version\":1}".utf8))
            }
            // Bytes this key cannot open. Reading them as plaintext and saving over them would
            // turn a recoverable fault into data loss.
            return ok(Data(repeating: 7, count: 200))
        }

        do {
            _ = try await service.loadDeck(for: "d1")
            XCTFail("expected the load to fail")
        } catch SlideContentError.decryptionFailed {
            // Expected.
        }
    }

    // MARK: - Save

    func testSaveSendsAMultipartBodyAndGuardsTheVersion() async throws {
        MockURLProtocol.respond(json: """
        {"id":"d1","name":"Kickoff","folderId":null,"sizeBytes":99,
         "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:05:00","contentVersion":8}
        """)
        let dek = Sodium().secretStream.xchacha20poly1305.key()

        let result = try await service.save(Fixture.deckContent(), to: "d1", dek: dek,
                                            expectedContentVersion: 7, title: "Renamed")

        XCTAssertEqual(result.contentVersion, 8)
        XCTAssertEqual(result.sizeBytes, 99)

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.query, "expectedContentVersion=7")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?
            .hasPrefix("multipart/form-data") ?? false)
        // The rename rides along in the same request rather than needing a second one.
        let body = String(decoding: MockURLProtocol.bodies[0], as: UTF8.self)
        XCTAssertTrue(body.contains("Renamed"))
        XCTAssertTrue(body.contains("slide.json"))
    }

    func testAVersionConflictIsReportedWithTheServersVersion() async throws {
        MockURLProtocol.respond(json: """
        {"error":{"code":"CONTENT_VERSION_CONFLICT","message":"expected 4, found 11"}}
        """, statusCode: 409)

        do {
            _ = try await service.save(Fixture.deckContent(), to: "d1",
                                       dek: Sodium().secretStream.xchacha20poly1305.key(),
                                       expectedContentVersion: 4)
            XCTFail("expected a conflict")
        } catch SlideContentError.contentVersionConflict(let current) {
            XCTAssertEqual(current, 11)
        }
    }

    func testAnUnrelated409IsNotReportedAsAStaleEdit() async throws {
        MockURLProtocol.respond(json: """
        {"error":{"code":"FILE_IN_TRASH","message":"cannot write to a trashed file"}}
        """, statusCode: 409)

        do {
            _ = try await service.save(Fixture.deckContent(), to: "d1",
                                       dek: Sodium().secretStream.xchacha20poly1305.key())
            XCTFail("expected an error")
        } catch SlideContentError.serverError(let status) {
            XCTAssertEqual(status, 409)
        }
    }
}
