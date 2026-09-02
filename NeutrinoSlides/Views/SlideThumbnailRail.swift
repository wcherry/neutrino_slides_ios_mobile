import SwiftUI
import UniformTypeIdentifiers

// MARK: - SlideThumbnailRail

/// The strip of slides under the canvas: where you are in the deck, and how you move around it.
///
/// Horizontal rather than the web app's vertical rail, because the space under a phone's canvas is
/// wide and short — the same reason the web puts it down the side of a window that is tall and
/// narrow beside its canvas.
struct SlideThumbnailRail: View {

    // MARK: - Input

    let slides: [Slide]
    let theme: SlideTheme
    let selectedIndex: Int
    let isEditable: Bool
    let onSelect: (Int) -> Void
    /// `source` and `destination` are the SwiftUI move convention: the destination is the index the
    /// slide should end up *before*.
    let onMove: (Int, Int) -> Void

    // MARK: - State

    /// The slide being dragged, so the rail can mark it while it travels.
    @State private var draggingIndex: Int?

    private static let thumbnailWidth: CGFloat = 104

    // MARK: - Body

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                        thumbnail(slide, index: index)
                            .id(slide.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            // Following the selection matters most when it moved for a reason other than a tap: an
            // undo, a slide added from the menu, or a deep link. A tapped thumbnail is already on
            // screen, so this is a no-op in the common case.
            .onChange(of: selectedIndex) { index in
                guard slides.indices.contains(index) else { return }
                withAnimation { scroller.scrollTo(slides[index].id, anchor: .center) }
            }
        }
        .frame(height: 96)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Pieces

    private func thumbnail(_ slide: Slide, index: Int) -> some View {
        let isSelected = index == selectedIndex
        let size = CGSize(width: Self.thumbnailWidth,
                          height: Self.thumbnailWidth / SlideGeometry.aspectRatio)

        return Button {
            onSelect(index)
        } label: {
            VStack(spacing: 4) {
                SlideCanvasView(slide: slide, theme: theme, size: size, showsBorder: true)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                    .opacity(draggingIndex == index ? 0.4 : 1)

                HStack(spacing: 3) {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    // The badge is the only place a transition is visible without presenting, and
                    // "none" is the default, so only a slide that actually does something is
                    // marked.
                    if let transition = badgeTransition(slide) {
                        Image(systemName: transition.iconName)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(slide, index: index))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .modifier(ReorderModifier(index: index, isEnabled: isEditable,
                                  draggingIndex: $draggingIndex, onMove: onMove))
    }

    private func badgeTransition(_ slide: Slide) -> SlideTransition? {
        let transition = SlideTransition(stored: slide.transition)
        return transition == .none ? nil : transition
    }

    private func accessibilityLabel(_ slide: Slide, index: Int) -> String {
        let title = slide.title ?? "Empty slide"
        return "Slide \(index + 1), \(title)"
    }
}

// MARK: - ReorderModifier

/// Drag-to-reorder for one thumbnail.
///
/// `onDrag` / `onDrop` rather than a `List`'s `onMove`, because the rail is not a list: it is a
/// horizontal stack of cards, and wrapping it in a `List` to borrow the gesture would cost the
/// layout, the sizing and the scroll behaviour that make it a rail.
///
/// The payload is the slide's *index* as text. It never leaves the app — the drop handler is the
/// same rail — so the simplest transferable item is enough, and an index is what the reorder needs.
private struct ReorderModifier: ViewModifier {

    let index: Int
    let isEnabled: Bool
    @Binding var draggingIndex: Int?
    let onMove: (Int, Int) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrag {
                    draggingIndex = index
                    return NSItemProvider(object: String(index) as NSString)
                }
                .onDrop(of: [.text], delegate: ReorderDropDelegate(
                    index: index, draggingIndex: $draggingIndex, onMove: onMove
                ))
        } else {
            content
        }
    }
}

// MARK: - ReorderDropDelegate

private struct ReorderDropDelegate: DropDelegate {

    let index: Int
    @Binding var draggingIndex: Int?
    let onMove: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        defer { draggingIndex = nil }
        guard let source = draggingIndex, source != index else { return false }
        // The model takes SwiftUI's insertion convention, where dropping *onto* slide `n` from
        // above means landing at `n + 1`.
        onMove(source, source < index ? index + 1 : index)
        return true
    }

    func dropEntered(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
