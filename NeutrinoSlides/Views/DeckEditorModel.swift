import Foundation
import Sodium
import os.log

// MARK: - DeckEditorModel

/// The state of one open deck: what was loaded, what has changed, and what is being written.
///
/// Kept out of the view because three of its responsibilities are genuinely stateful and easy to
/// get wrong in a `View`'s `@State`:
///
/// - **The save chain.** Never two autosave PUTs in flight at once. The web app hit real body
///   truncation doing that (see `usePersistence`'s `saveChainRef` in the Sheets editor, which the
///   Slides editor's autosave shares), and the same shape of bug on a phone would silently drop an
///   edit.
/// - **Conflict.** A 409 is a decision for the user, not something to retry into.
/// - **Editing.** Every mutation goes through one funnel (``apply(name:slideIndexAfter:elementAfter:_:)``) so
///   that undo, the dirty flag and the selection cannot fall out of step with the slides — which is
///   exactly what happens when each command mutates the deck its own way.
@MainActor
final class DeckEditorModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var deck: SlideDeck?
    @Published private(set) var info: SlideFileInfo?
    /// Which slide is showing. Always a valid index while a deck is loaded, because every path that
    /// changes the slide list clamps it.
    @Published private(set) var selectedSlideIndex: Int = 0
    /// The selected element on the current slide, or nil when the slide itself is selected.
    @Published private(set) var selectedElementID: String?

    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasUnsavedChanges = false
    @Published var loadError: String?
    @Published var saveError: String?
    /// A short, self-clearing message for something worth saying but not worth interrupting for —
    /// "Slide deleted", or the note that a pasted element landed off the slide.
    @Published private(set) var notice: String?
    /// Set when the server refused a save because the deck moved on elsewhere. Surfaced to the
    /// user, never resolved silently — overwriting is not this app's decision to make.
    @Published var conflict: ConflictState?

    /// Bumped on every recorded edit, purely so SwiftUI re-reads ``canUndo`` / ``canRedo``. The
    /// history itself is a value type inside a non-published property; without this the toolbar
    /// buttons would keep whatever enabled state they were first drawn with.
    @Published private(set) var historyToken = 0

    struct ConflictState: Identifiable {
        let id = UUID()
        /// The version the server holds now, when it could be recovered from the error body.
        let serverVersion: Int?
    }

    // MARK: - Dependencies

    private let item: SlideItem
    private var contentService: SlideContentService
    private weak var driveService: SlidesDriveService?

    // MARK: - Session state

    /// The deck's DEK, held for the session so a save needs neither a re-fetch nor a re-unseal.
    private var dek: Bytes?
    /// The version the loaded content was read at, sent as `expectedContentVersion` on the next save
    /// and advanced by each successful one.
    private var contentVersion: Int?
    /// True until a sealed package has replaced a body that was empty or unreadable at load.
    private var needsInitialEncryption = false

    /// Epic 7 — "Undo / redo".
    private var history = EditHistory()

    /// The chain every save links onto, so no two writes overlap. Awaiting the previous task before
    /// starting the next is the whole mechanism.
    private var saveChain: Task<Void, Never>?

    /// True between a save being queued and it starting to run.
    ///
    /// Used to coalesce: a save that has not begun yet will serialise whatever the deck holds at the
    /// moment it does, so queueing a second one behind it would upload identical bytes twice.
    /// Without this, a single edit produces two PUTs — the timer's and the flush's.
    private var isSaveQueued = false

    /// Clears ``notice`` after a beat, cancelled and restarted by each new one.
    private var noticeTask: Task<Void, Never>?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NeutrinoSlides",
                                category: "DeckEditorModel")

    // MARK: - Init

    init(item: SlideItem, contentService: SlideContentService, driveService: SlidesDriveService?) {
        self.item = item
        self.contentService = contentService
        self.driveService = driveService
    }

    /// Re-points the model at the environment's services.
    ///
    /// The view constructs this model in its `init`, where `@EnvironmentObject` is not yet readable,
    /// so it starts with a placeholder content service and no drive service. This is called from
    /// `.task`, before ``load()``, and is idempotent.
    func attach(contentService: SlideContentService, driveService: SlidesDriveService?) {
        self.contentService = contentService
        self.driveService = driveService
    }

    // MARK: - Derived

    /// The name without its `.pptx`, which is file plumbing rather than part of the title.
    var title: String { PptxCodec.strippingExtension(info?.name ?? item.name) }

    /// Whether this account may write to the deck. A presentation shared read-only opens in a
    /// viewer, and every editing affordance is hidden rather than disabled-on-tap.
    var isEditable: Bool {
        FeatureFlags.deckEditing && (info?.isEditable ?? false)
    }

    var slides: [Slide] { deck?.slides ?? [] }

    var theme: SlideTheme { deck?.theme ?? .default }

    var master: SlideMaster { deck?.effectiveMaster ?? .default }

    var currentSlide: Slide? {
        guard slides.indices.contains(selectedSlideIndex) else { return nil }
        return slides[selectedSlideIndex]
    }

    var selectedElement: SlideElement? {
        guard let selectedElementID else { return nil }
        return currentSlide?.element(id: selectedElementID)
    }

    /// The selection as the history records it, so an undo can put it back.
    private var selection: DeckSelection? {
        guard let slide = currentSlide else { return nil }
        return DeckSelection(slideID: slide.id, elementID: selectedElementID)
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var undoName: String? { history.undoName }
    var redoName: String? { history.redoName }

    /// Whether a slide can be removed — a deck has to keep one, the same rule the web app enforces.
    var canDeleteSlide: Bool { slides.count > 1 }

    // MARK: - Loading

    func load() async {
        guard !isLoading, deck == nil else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let loaded = try await contentService.loadDeck(for: item.id)
            deck = loaded.file
            info = loaded.info
            dek = loaded.dek
            contentVersion = loaded.info.contentVersion
            needsInitialEncryption = loaded.needsInitialEncryption
            selectedSlideIndex = 0
            selectedElementID = nil
            history.clear()

            // A presentation with no sealed package yet — created moments ago with no body at all
            // — gets one first, before the user can change anything. Through the save chain, so it
            // can never race a save triggered moments later by a fast edit.
            if needsInitialEncryption {
                logger.debug("load: id=\(self.item.id, privacy: .public) needs initial encryption")
                queueSave()
            }
        } catch {
            logger.error("load failed: \(error, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    // MARK: - Selection

    func selectSlide(at index: Int) {
        guard slides.indices.contains(index) else { return }
        selectedSlideIndex = index
        // An element id names an element on the slide it was selected on; carrying it to another
        // slide would either select nothing or, worse, select a *different* element that a
        // duplicate happens to share an id with.
        selectedElementID = nil
    }

    func select(elementID: String?) {
        guard let elementID else {
            selectedElementID = nil
            return
        }
        guard currentSlide?.element(id: elementID) != nil else { return }
        selectedElementID = elementID
    }

    // MARK: - Slides

    /// Epic 8 — adds a slide after the current one, taking the theme's background and transition,
    /// exactly as the web app's `addSlide` does.
    func addSlide() {
        guard isEditable, let deck else { return }
        let slide = Slide(background: deck.theme.slideBackground,
                          elements: [],
                          transition: deck.theme.defaultTransition)
        let index = selectedSlideIndex + 1
        apply(name: "Add Slide", slideIndexAfter: index, elementAfter: nil) { slides in
            slides.insert(slide, at: min(index, slides.count))
        }
    }

    func duplicateSlide() {
        guard isEditable, let slide = currentSlide else { return }
        let copy = slide.duplicated()
        let index = selectedSlideIndex + 1
        apply(name: "Duplicate Slide", slideIndexAfter: index, elementAfter: nil) { slides in
            slides.insert(copy, at: min(index, slides.count))
        }
    }

    func deleteSlide() {
        guard isEditable, canDeleteSlide, slides.indices.contains(selectedSlideIndex) else { return }
        let index = selectedSlideIndex
        apply(name: "Delete Slide", slideIndexAfter: max(0, index - 1), elementAfter: nil) { slides in
            slides.remove(at: index)
        }
        show(notice: "Slide deleted")
    }

    /// Moves the current slide one place in `direction` (-1 up, +1 down).
    func moveSlide(by direction: Int) {
        guard isEditable else { return }
        let from = selectedSlideIndex
        let to = from + direction
        guard slides.indices.contains(from), slides.indices.contains(to) else { return }
        apply(name: "Move Slide", slideIndexAfter: to, elementAfter: selectedElementID) { slides in
            slides.swapAt(from, to)
        }
    }

    /// Drag-to-reorder in the thumbnail rail.
    func moveSlide(from source: Int, to destination: Int) {
        guard isEditable, slides.indices.contains(source) else { return }
        // `destination` is SwiftUI's insertion index, which is one past the end when a row is
        // dropped last and is *before* the removal when moving down the list.
        let clamped = min(max(0, destination), slides.count)
        guard clamped != source, clamped != source + 1 else { return }
        let landing = clamped > source ? clamped - 1 : clamped
        apply(name: "Reorder Slides", slideIndexAfter: landing,
              elementAfter: selectedElementID) { slides in
            let slide = slides.remove(at: source)
            slides.insert(slide, at: landing)
        }
    }

    // MARK: - Slide properties

    func setBackground(_ background: SlideBackground) {
        guard isEditable, let slide = currentSlide, slide.background != background else { return }
        editCurrentSlide(name: "Background") { $0.background = background }
    }

    func setTransition(_ transition: SlideTransition) {
        guard isEditable, let slide = currentSlide,
              slide.transition != transition.rawValue else { return }
        editCurrentSlide(name: "Transition") { $0.transition = transition.rawValue }
    }

    /// Speaker notes. Called as the user types, so a no-op write is dropped before it can put an
    /// empty edit in the history.
    func setNotes(_ notes: String) {
        guard isEditable, let slide = currentSlide, slide.notes != notes else { return }
        editCurrentSlide(name: "Speaker Notes") { $0.notes = notes }
    }

    // MARK: - Layouts and themes

    /// Epic 8 — applying a layout **replaces** the slide's elements, as it does on the web.
    func applyLayout(_ layout: SlideLayout) {
        guard isEditable, let deck else { return }
        let elements = layout.makeElements(deck.theme, deck.effectiveMaster)
        editCurrentSlide(name: "Apply Layout", selection: .clear) { $0.elements = elements }
    }

    /// Epic 10 — restyles the whole deck. See ``ThemeApplication/apply(_:to:)`` for what it does and
    /// does not touch.
    func applyTheme(_ theme: SlideTheme) {
        guard isEditable, let deck, deck.theme != theme else { return }
        let updated = ThemeApplication.apply(theme, to: deck)
        record(DeckEdit(before: deck.slides, after: updated.slides,
                        themeBefore: deck.theme, themeAfter: theme,
                        selectionBefore: selection, selectionAfter: selection,
                        name: "Apply Theme"))
        self.deck = updated
        markEdited()
        show(notice: "Theme \u{201C}\(theme.name)\u{201D} applied")
    }

    /// Epic 10 — the slide master's "apply to all slides".
    func applyMaster(_ master: SlideMaster) {
        guard isEditable, let deck else { return }
        let updated = ThemeApplication.applyMaster(master, to: deck)
        guard updated.slides != deck.slides || updated.master != deck.master else { return }
        record(DeckEdit(before: deck.slides, after: updated.slides,
                        masterBefore: deck.master ?? .default, masterAfter: master,
                        selectionBefore: selection, selectionAfter: selection,
                        name: "Apply Master"))
        self.deck = updated
        markEdited()
    }

    // MARK: - Elements

    /// Epic 7 — "Add a text box".
    func addTextBox() {
        guard isEditable, let slide = currentSlide else { return }
        let frame = SlideGeometry.placement(size: SlideFrame(x: 0, y: 0, w: 50, h: 15),
                                            existingCount: slide.elements.count)
        let element = TextElement(
            frame: frame,
            content: "New text",
            style: TextStyle(fontSize: master.bodyFontSize, bold: master.bodyBold,
                             color: master.bodyColor, align: "left", fontFamily: theme.fontFamily)
        )
        insert(.text(element), name: "Add Text")
    }

    /// Epic 7 — "Add a shape".
    func addShape(_ key: String = ShapeCatalog.defaultKey) {
        guard isEditable, let slide = currentSlide else { return }
        let frame = SlideGeometry.placement(size: SlideFrame(x: 0, y: 0, w: 25, h: 25),
                                            existingCount: slide.elements.count)
        let element = ShapeElement(shape: key, frame: frame, fill: theme.primaryColor,
                                   stroke: "transparent", strokeWidth: 0)
        insert(.shape(element), name: "Add Shape")
    }

    /// Epic 7 — "Add a line", from the line catalog's presets.
    func addLine(dash: String? = nil, startArrow: String? = nil, endArrow: String? = nil) {
        guard isEditable else { return }
        let element = LineElement(x1: 20, y1: 50, x2: 80, y2: 50,
                                  stroke: theme.textColor, strokeWidth: 2, strokeDash: dash,
                                  startArrow: startArrow, endArrow: endArrow)
        insert(.line(element), name: "Add Line")
    }

    private func insert(_ element: SlideElement, name: String) {
        editCurrentSlide(name: name, selection: .element(element.id)) { $0.elements.append(element) }
    }

    func deleteSelectedElement() {
        guard isEditable, let id = selectedElementID else { return }
        editCurrentSlide(name: "Delete Element", selection: .clear) { slide in
            slide.elements.removeAll { $0.id == id }
        }
    }

    func duplicateSelectedElement() {
        guard isEditable, let element = selectedElement else { return }
        // Offset so the copy is visibly a second object rather than sitting exactly on the
        // original, where the only way to find it is to drag the one on top.
        let copy = element.withNewID()
        let offset = copy.frame.map { $0.offset(by: 2.5, 2.5).clampedToCanvas() }
        let placed = offset.map { copy.withFrame($0) } ?? copy
        editCurrentSlide(name: "Duplicate Element", selection: .element(placed.id)) { slide in
            slide.elements.append(placed)
        }
    }

    /// Epic 8 — z-order. `offset` of +1 moves the element one step towards the front.
    func reorderSelectedElement(by offset: Int) {
        guard isEditable, let id = selectedElementID, let slide = currentSlide,
              let index = slide.index(ofElement: id) else { return }
        let target = index + offset
        guard slide.elements.indices.contains(target) else { return }
        editCurrentSlide(name: offset > 0 ? "Bring Forward" : "Send Backward",
                         selection: .element(id)) { slide in
            slide.elements.swapAt(index, target)
        }
    }

    /// Moves the element to the very front or the very back.
    func sendSelectedElement(toFront: Bool) {
        guard isEditable, let id = selectedElementID, let slide = currentSlide,
              let index = slide.index(ofElement: id) else { return }
        guard toFront ? index < slide.elements.count - 1 : index > 0 else { return }
        editCurrentSlide(name: toFront ? "Bring to Front" : "Send to Back",
                         selection: .element(id)) { slide in
            let element = slide.elements.remove(at: index)
            if toFront {
                slide.elements.append(element)
            } else {
                slide.elements.insert(element, at: 0)
            }
        }
    }

    // MARK: - Geometry

    /// Commits a drag or a resize.
    ///
    /// Called once at the *end* of the gesture, not on every change: the view draws the in-progress
    /// frame itself, so a drag across the slide is one undo step rather than sixty.
    func setFrame(_ frame: SlideFrame, forElement id: String, name: String = "Move") {
        guard isEditable, let slide = currentSlide, let index = slide.index(ofElement: id),
              slide.elements[index].frame != frame else { return }
        editCurrentSlide(name: name, selection: .element(id)) { slide in
            slide.elements[index] = slide.elements[index].withFrame(frame)
        }
    }

    /// Nudges the selected element, for the arrow-key and accessibility paths.
    func nudgeSelectedElement(dx: Double, dy: Double) {
        guard let element = selectedElement, let frame = element.frame else { return }
        setFrame(frame.offset(by: dx, dy).clampedToCanvas(), forElement: element.id)
    }

    // MARK: - Text

    /// Commits the text typed into a box.
    func setText(_ content: String, forElement id: String) {
        guard isEditable, let slide = currentSlide, let index = slide.index(ofElement: id),
              case .text(let existing) = slide.elements[index], existing.content != content else {
            return
        }
        editCurrentSlide(name: "Edit Text", selection: .element(id)) { slide in
            guard case .text(var text) = slide.elements[index] else { return }
            text.content = content
            slide.elements[index] = .text(text)
        }
    }

    /// Epic 9 — applies a style patch to the selected text box.
    func applyTextStyle(_ patch: TextStylePatch, name: String) {
        guard isEditable, !patch.isEmpty, let id = selectedElementID,
              let slide = currentSlide, let index = slide.index(ofElement: id),
              case .text(let existing) = slide.elements[index] else { return }
        let updated = patch.applied(to: existing.style)
        guard updated != existing.style else { return }
        editCurrentSlide(name: name, selection: .element(id)) { slide in
            guard case .text(var text) = slide.elements[index] else { return }
            text.style = updated
            slide.elements[index] = .text(text)
        }
    }

    /// The size step buttons. Reads the current size rather than taking one, so the two buttons
    /// cannot disagree about what "one step bigger" means.
    func stepFontSize(by delta: Double) {
        guard let style = selectedElement?.text?.style else { return }
        applyTextStyle(.size(style.fontSize + delta),
                       name: delta > 0 ? "Increase Size" : "Decrease Size")
    }

    // MARK: - Shapes

    func setShapeFill(_ fill: String) {
        guard isEditable, let id = selectedElementID, let slide = currentSlide,
              let index = slide.index(ofElement: id),
              case .shape(let existing) = slide.elements[index], existing.fill != fill else { return }
        editCurrentSlide(name: "Shape Fill", selection: .element(id)) { slide in
            guard case .shape(var shape) = slide.elements[index] else { return }
            shape.fill = fill
            slide.elements[index] = .shape(shape)
        }
    }

    func setShapeStroke(_ stroke: String?, width: Double?) {
        guard isEditable, let id = selectedElementID, let slide = currentSlide,
              let index = slide.index(ofElement: id),
              case .shape(let existing) = slide.elements[index] else { return }
        let newStroke = stroke ?? existing.stroke
        let newWidth = width ?? existing.strokeWidth
        guard newStroke != existing.stroke || newWidth != existing.strokeWidth else { return }
        editCurrentSlide(name: "Shape Border", selection: .element(id)) { slide in
            guard case .shape(var shape) = slide.elements[index] else { return }
            shape.stroke = newStroke
            shape.strokeWidth = newWidth
            slide.elements[index] = .shape(shape)
        }
    }

    /// Swaps a shape for another from the catalog, keeping its position and colours.
    func setShapeKind(_ key: String) {
        guard isEditable, let id = selectedElementID, let slide = currentSlide,
              let index = slide.index(ofElement: id),
              case .shape(let existing) = slide.elements[index], existing.shape != key else { return }
        editCurrentSlide(name: "Change Shape", selection: .element(id)) { slide in
            guard case .shape(var shape) = slide.elements[index] else { return }
            shape.shape = key
            slide.elements[index] = .shape(shape)
        }
    }

    /// The line colour and weight, for a selected line.
    func setLineStroke(_ stroke: String?, width: Double?) {
        guard isEditable, let id = selectedElementID, let slide = currentSlide,
              let index = slide.index(ofElement: id),
              case .line(let existing) = slide.elements[index] else { return }
        let newStroke = stroke ?? existing.stroke
        let newWidth = width ?? existing.strokeWidth
        guard newStroke != existing.stroke || newWidth != existing.strokeWidth else { return }
        editCurrentSlide(name: "Line Style", selection: .element(id)) { slide in
            guard case .line(var line) = slide.elements[index] else { return }
            line.stroke = newStroke
            line.strokeWidth = newWidth
            slide.elements[index] = .line(line)
        }
    }

    // MARK: - Undo / redo

    func undo() {
        guard let edit = history.undo() else { return }
        restore(edit, undoing: true)
    }

    func redo() {
        guard let edit = history.redo() else { return }
        restore(edit, undoing: false)
    }

    /// Puts one side of an edit back.
    private func restore(_ edit: DeckEdit, undoing: Bool) {
        guard var deck else { return }
        deck.slides = undoing ? edit.before : edit.after
        if edit.changesTheme, let theme = undoing ? edit.themeBefore : edit.themeAfter {
            deck.theme = theme
        }
        if edit.changesMaster {
            deck.master = undoing ? edit.masterBefore : edit.masterAfter
        }
        self.deck = deck
        restoreSelection(undoing ? edit.selectionBefore : edit.selectionAfter)
        historyToken &+= 1
        hasUnsavedChanges = true
    }

    /// Puts the selection back by *id*, not by index.
    ///
    /// An index recorded before a reorder points at a different slide afterwards, and one recorded
    /// before a delete can point past the end. The id either still exists — in which case it is the
    /// right slide, wherever it has moved to — or it does not, in which case the closest valid index
    /// is the only sensible answer.
    private func restoreSelection(_ selection: DeckSelection?) {
        guard let selection else {
            selectedSlideIndex = min(selectedSlideIndex, max(0, slides.count - 1))
            selectedElementID = nil
            return
        }
        if let index = deck?.index(ofSlide: selection.slideID) {
            selectedSlideIndex = index
        } else {
            selectedSlideIndex = min(selectedSlideIndex, max(0, slides.count - 1))
        }
        selectedElementID = selection.elementID.flatMap { id in
            currentSlide?.element(id: id) != nil ? id : nil
        }
    }

    // MARK: - Applying changes

    /// The single funnel every edit passes through.
    ///
    /// - Parameters:
    ///   - name: what undo will be called.
    ///   - slideIndexAfter: where to leave the selection. Defaults to where it is.
    ///   - elementAfter: which element to leave selected, `nil` for none.
    ///   - transform: mutates the slide list in place.
    ///
    /// An edit that changes nothing is dropped, which keeps a no-op — retyping the same text,
    /// dragging an element back where it started — out of the history and off the save queue.
    private func apply(name: String, slideIndexAfter: Int? = nil, elementAfter: String?,
                       _ transform: (inout [Slide]) -> Void) {
        guard isEditable, var deck else { return }
        let before = deck.slides
        var slides = before
        transform(&slides)
        guard slides != before else { return }

        let selectionBefore = selection
        deck.slides = slides
        self.deck = deck

        // Clamped after the transform, since the list it indexes into is the new one.
        let index = min(max(0, slideIndexAfter ?? selectedSlideIndex), max(0, slides.count - 1))
        selectedSlideIndex = index
        selectedElementID = elementAfter.flatMap { id in
            currentSlide?.element(id: id) != nil ? id : nil
        }

        record(DeckEdit(before: before, after: slides,
                        selectionBefore: selectionBefore, selectionAfter: selection, name: name))
        markEdited()
    }

    /// What an edit leaves selected.
    ///
    /// Spelled out rather than passed as an optional id, because "leave the selection alone" and
    /// "select nothing" are different instructions and an optional can only carry one of them: a
    /// background change keeps the selected element, applying a layout must not.
    enum SelectionAfter {
        case keep
        case clear
        case element(String)

        fileprivate func resolve(current: String?) -> String? {
            switch self {
            case .keep:                return current
            case .clear:               return nil
            case .element(let id):     return id
            }
        }
    }

    /// The common case: an edit to the slide that is showing.
    private func editCurrentSlide(name: String, selection: SelectionAfter = .keep,
                                  _ transform: (inout Slide) -> Void) {
        let index = selectedSlideIndex
        let element = selection.resolve(current: selectedElementID)
        apply(name: name, elementAfter: element) { slides in
            guard slides.indices.contains(index) else { return }
            transform(&slides[index])
        }
    }

    private func record(_ edit: DeckEdit) {
        history.record(edit)
        historyToken &+= 1
    }

    private func markEdited() {
        hasUnsavedChanges = true
    }

    // MARK: - Notices

    private func show(notice message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Saving

    /// Queues a save behind whatever is already in flight.
    ///
    /// Every path into saving goes through here — the timer, the manual save, and the
    /// leaving-the-editor flush — because that is the only way to be sure two PUTs are never on the
    /// wire at once.
    func queueSave() {
        guard !isSaveQueued else { return }
        isSaveQueued = true
        let previous = saveChain
        saveChain = Task { [weak self] in
            await previous?.value
            await self?.performSave()
        }
    }

    /// Saves if anything has changed. The autosave timer calls this.
    func saveIfNeeded() {
        guard hasUnsavedChanges, conflict == nil else { return }
        queueSave()
    }

    /// Waits for every queued save to finish. Called when the editor is going away, so an edit made
    /// a moment before leaving is not lost.
    func flush() async {
        saveIfNeeded()
        await saveChain?.value
    }

    private func performSave() async {
        // Released here rather than at the end: from this point the save is reading current state,
        // so an edit that lands during the upload does need a save of its own.
        isSaveQueued = false
        guard let deck, let dek, isEditable else { return }
        // A conflict is unresolved until the user says otherwise; saving over it is exactly what
        // must not happen.
        guard conflict == nil else { return }

        isSaving = true
        saveError = nil
        defer { isSaving = false }

        // Cleared *before* the request, not after: an edit made while the upload is in flight has
        // to leave the flag set, and clearing afterwards would swallow it.
        hasUnsavedChanges = false

        do {
            let result = try await contentService.save(deck, to: item.id, dek: dek,
                                                       expectedContentVersion: contentVersion)
            contentVersion = result.contentVersion
            needsInitialEncryption = false
            driveService?.presentationWasSaved(itemID: item.id, size: result.sizeBytes,
                                               modifiedAt: result.updatedAt,
                                               contentVersion: result.contentVersion)
            logger.debug("save succeeded: id=\(self.item.id, privacy: .public)")
        } catch let error as SlideContentError {
            hasUnsavedChanges = true
            if case .contentVersionConflict(let current) = error {
                logger.error("save conflict: id=\(self.item.id, privacy: .public)")
                conflict = ConflictState(serverVersion: current)
            } else {
                logger.error("save failed: \(error, privacy: .public)")
                saveError = error.localizedDescription
            }
        } catch {
            hasUnsavedChanges = true
            logger.error("save failed: \(error, privacy: .public)")
            saveError = error.localizedDescription
        }
    }

    // MARK: - Conflict resolution

    /// Throws away this device's edits and re-reads the server's copy.
    func reloadAfterConflict() async {
        conflict = nil
        deck = nil
        hasUnsavedChanges = false
        // The history describes slides that are about to be replaced wholesale; undoing into them
        // afterwards would write this device's discarded edits back over the server's copy.
        history.clear()
        historyToken &+= 1
        await load()
    }

    /// Keeps this device's copy, overwriting whatever landed on the server.
    ///
    /// Done by dropping the version guard for one save: the point of `expectedContentVersion` is to
    /// stop an *unintended* overwrite, and this one is intended.
    func keepLocalCopyAfterConflict() {
        guard let serverVersion = conflict?.serverVersion else {
            // Without the server's version there is nothing to guard against, so the save goes
            // unguarded — which is what the user just asked for.
            contentVersion = nil
            conflict = nil
            queueSave()
            return
        }
        contentVersion = serverVersion
        conflict = nil
        queueSave()
    }
}
