import Foundation
import NeutrinoOOXML

// MARK: - PptxCodec

/// The one door in and out of the `.pptx` a Neutrino presentation is stored as.
///
/// A presentation is a real PowerPoint deck (issue #127): the mime type is ``mimeType``, the
/// extension rides on the Drive file's *name* so a download lands on disk as something the operating
/// system can open, and every other office suite opens one directly.
///
/// ## Two copies of one deck
///
/// What the web editor can *write* as PresentationML is a lossy projection of what it can hold —
/// themes, transitions it has no OOXML name for, gradient fills, anything a later release adds. So
/// a package carries both halves, exactly as `web/apps/web/src/lib/ooxmlContainer.ts` lays it out:
///
/// - the PresentationML parts, the interoperable copy PowerPoint and Keynote read;
/// - one extra part, ``modelPart``, holding the editor's own full-fidelity ``SlideDeck`` JSON.
///
/// On open the model wins, so nothing is lost across a save in either Neutrino client. When it is
/// missing — a deck made in PowerPoint, or one PowerPoint re-saved, since it drops parts it does not
/// recognise — ``PptxReader`` parses the slides instead. That path is correct, just lossy.
///
/// A tool that *kept* the part while rewriting the slides would be worse than one that dropped it:
/// a stale model would quietly overwrite the outside edit. ``digest(of:)`` closes that off — it
/// fingerprints every other part at save time, and a model whose digest no longer matches the
/// package it sits in is ignored exactly as if it were absent.
///
/// Unlike the spreadsheet codec, slides has not yet moved off the model part on the web, so this
/// writes one as well as reading it. Leaving it out would make every save from a phone strip the
/// deck's theme and transitions for the web.
enum PptxCodec {

    // MARK: - Identity

    /// What Drive stores a Neutrino presentation as.
    static let mimeType =
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"

    static let fileExtension = "pptx"

    /// The part holding the editor's own model. Not an OOXML part — see above.
    static let modelPart = "neutrino/model.json"

    /// The `app` a model envelope must name to be this app's. A `.docx` from before the docs
    /// writer landed carries the same part path with `"docs"` in it.
    static let modelApp = "slides"

    // MARK: - Reading

    /// Reads `.pptx` bytes into a deck.
    ///
    /// A package carrying a trustworthy model part yields that model; everything else is read from
    /// the slide parts. Throws only when the bytes are not a package at all.
    static func decode(_ data: Data) throws -> SlideDeck {
        let zip = try ZipArchive(data: data)
        if let model = model(in: zip) { return model }
        return PptxReader.read(zip)
    }

    /// Whether these bytes are a package at all — the cheap check before reading, and how a
    /// plaintext body is told apart from ciphertext without trying to decrypt it.
    static func isPackage(_ data: Data) -> Bool { ZipArchive.looksLikeArchive(data) }

    // MARK: - Writing

    /// Renders `deck` as `.pptx` bytes, with the model packed in beside the slides.
    static func encode(_ deck: SlideDeck) throws -> Data {
        var zip = PptxWriter.write(deck)
        try pack(deck, into: &zip)
        return try zip.serialized()
    }

    /// Adds the model part to `zip`, replacing any already there.
    ///
    /// The `.json` content type is declared *before* the digest is taken: the digest has to cover the
    /// package as it will be stored, or every read would see a mismatch and throw away the model
    /// this just wrote.
    static func pack(_ deck: SlideDeck, into zip: inout ZipArchive) throws {
        zip.remove(modelPart)
        if let types = zip.text(for: OOXMLPackage.contentTypesPart),
           types.range(of: "Extension=\"json\"", options: .caseInsensitive) == nil,
           let open = types.range(of: "<Types\\b[^>]*>", options: .regularExpression) {
            var declared = types
            declared.insert(contentsOf: jsonContentType, at: open.upperBound)
            zip.set(OOXMLPackage.contentTypesPart, text: declared)
        }

        let envelope: [String: Any] = [
            "version": 1,
            "app": modelApp,
            "digest": digest(of: zip),
            // A *string* of JSON, not a nested object: the envelope holds the same serialisation the
            // editors stored before OOXML, and the web reads it back with `JSON.parse(model)`.
            "model": String(decoding: try deck.encoded(), as: UTF8.self),
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope,
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        zip.set(modelPart, data: data)
    }

    /// `[Content_Types].xml` must give every extension in the package a content type, or the
    /// package is malformed and PowerPoint offers to repair it.
    private static let jsonContentType = "<Default Extension=\"json\" ContentType=\"application/json\"/>"

    /// A valid one-slide `.pptx` — what a newly created presentation holds from its first save.
    static func emptyPresentation() throws -> Data {
        try encode(.empty)
    }

    // MARK: - Names

    /// `name` with `.pptx` on the end, added only if it is not already there.
    ///
    /// The extension is part of the *file* name because a download has to land on disk as
    /// `Kickoff.pptx` to open on a double-click. Renaming "Kickoff" twice must not produce
    /// `Kickoff.pptx.pptx`.
    static func withExtension(_ name: String) -> String {
        hasExtension(name) ? name : "\(name).\(fileExtension)"
    }

    /// `name` without a trailing `.pptx` — the title to show for a file, which is what the web's
    /// `stripOoxmlExtension` does. A legacy `.ppt` keeps its name: only the modern extension goes.
    static func strippingExtension(_ name: String) -> String {
        hasExtension(name) ? String(name.dropLast(fileExtension.count + 1)) : name
    }

    private static func hasExtension(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".\(fileExtension)")
    }

    // MARK: - The model part

    /// The deck stored in `zip`'s model part, or nil when there is none to trust — a package written
    /// by another tool, one whose model belongs to a different editor, or one whose parts have
    /// changed since the model was written.
    ///
    /// Every nil means the same thing to the caller: read the slides instead.
    static func model(in zip: ZipArchive) -> SlideDeck? {
        guard let raw = zip.data(for: modelPart),
              let envelope = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              (envelope["version"] as? NSNumber)?.intValue == 1,
              envelope["app"] as? String == modelApp,
              let model = envelope["model"] as? String,
              envelope["digest"] as? String == digest(of: zip),
              let deck = try? JSONDecoder().decode(SlideDeck.self, from: Data(model.utf8)),
              !deck.slides.isEmpty
        else { return nil }
        return deck
    }

    /// FNV-1a over every part except the model, name included, in a fixed order.
    ///
    /// Not a cryptographic hash and not meant to be: the question it answers is "did something
    /// rewrite this package behind our back", where the alternative to a cheap answer is no answer
    /// at all. Names are hashed alongside contents so an added or removed part registers even when
    /// nothing else moved. This must agree byte for byte with `digestParts` in
    /// `web/apps/web/src/lib/ooxmlContainer.ts`, or each client would discard the other's model.
    static func digest(of zip: ZipArchive) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x100_0000_01b3
        func mix(_ byte: UInt8) {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        for name in zip.names.sorted() where name != modelPart {
            for byte in Array(name.utf8) { mix(byte) }
            for byte in zip.data(for: name) ?? Data() { mix(byte) }
        }
        return String(format: "%016lx", hash)
    }
}
