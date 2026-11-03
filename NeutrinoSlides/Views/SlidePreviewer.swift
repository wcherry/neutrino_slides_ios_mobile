import SwiftUI
import NeutrinoCore

// MARK: - SlidePreviewer

/// Keeps the deck's Drive preview — the picture in the Drive grid — showing its first slide.
///
/// The picture is slide one drawn by the same ``SlideCanvasView`` the editor and the thumbnail rail
/// use. *When* it is redrawn is ``DocumentPreviewGate``'s, the same rule the web editor follows: on
/// load only when the file has no preview, and after a save only when slide one changed — editing
/// slide nine redraws nothing.
@MainActor
final class SlidePreviewer {

    private let gate: DocumentPreviewGate
    /// The slide the next render draws: the one the latest signature was taken from.
    private var slide: Slide?
    private var theme: SlideTheme = .default

    init(fileID: String, contentService: SlideContentService) {
        var render: DocumentPreviewGate.Render = { nil }
        gate = DocumentPreviewGate(
            render: { await render() },
            upload: { [contentService] jpeg in try await contentService.setPreview(jpeg, for: fileID) }
        )
        render = { [weak self] in await self?.renderSlideOne() }
    }

    /// The deck is on screen: records slide one, or draws it if the file has no preview.
    /// Skipped for a reader, whose upload the server would refuse.
    func loaded(_ deck: SlideDeck, hasPreview: Bool, canEdit: Bool) {
        guard canEdit || hasPreview else { return }
        let signature = remember(deck)
        Task { await gate.loaded(signature: signature, hasPreview: hasPreview) }
    }

    /// A save landed: redraws slide one if it changed.
    func saved(_ deck: SlideDeck, hasPreview: Bool) {
        let signature = remember(deck)
        Task { await gate.saved(signature: signature, hasPreview: hasPreview) }
    }

    /// Slide one and the theme it falls back to, as a signature. The models are `Hashable` and a
    /// signature only has to be compared within this session, so their hashes serve.
    private func remember(_ deck: SlideDeck) -> String {
        slide = deck.slides.first
        theme = deck.theme
        return "\(deck.slides.first?.hashValue ?? 0)-\(deck.theme.hashValue)"
    }

    private func renderSlideOne() -> Data? {
        guard let slide else { return nil }
        let width = CGFloat(DriveThumbnail.maxEdge)
        let size = CGSize(width: width, height: width / SlideGeometry.aspectRatio)
        let renderer = ImageRenderer(content: SlideCanvasView(slide: slide, theme: theme, size: size)
            .environment(\.colorScheme, .light))
        renderer.scale = 1
        return renderer.uiImage?.jpegData(compressionQuality: 0.82)
    }
}
