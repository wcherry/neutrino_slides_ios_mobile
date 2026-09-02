import Foundation

// MARK: - DeckSelection

/// What the editor is pointed at: a slide, and optionally an element on it.
///
/// Carried through the history because undoing a change to a slide three slides back, without
/// going back to it, shows the user nothing happening.
struct DeckSelection: Hashable {
    var slideID: String
    var elementID: String?

    init(slideID: String, elementID: String? = nil) {
        self.slideID = slideID
        self.elementID = elementID
    }
}

// MARK: - DeckEdit

/// One undoable change to a deck.
///
/// Recorded as a **snapshot of the slide list**, not as a patch. That is the opposite of what
/// Neutrino Sheets does, and the difference is the shape of the data rather than a difference of
/// opinion: a spreadsheet is tens of thousands of cells of which an edit touches one, so a snapshot
/// there would be megabytes per keystroke. A deck is tens of slides holding a handful of elements
/// each, and its edits routinely rearrange whole slides — applying a layout replaces every element
/// on one, applying a theme touches every element in the deck. A patch format able to describe
/// those would be a reimplementation of the snapshot with more ways to be wrong.
///
/// The snapshot is cheaper than it looks: ``Slide`` is a value type, so the slides an edit did not
/// touch share storage with the ones already held.
struct DeckEdit {

    /// The slide list before and after.
    let before: [Slide]
    let after: [Slide]

    /// The deck-level state an edit can also change: the theme and the master. Nil on both sides
    /// for the great majority of edits, which touch neither.
    let themeBefore: SlideTheme?
    let themeAfter: SlideTheme?
    let masterBefore: SlideMaster?
    let masterAfter: SlideMaster?

    let selectionBefore: DeckSelection?
    let selectionAfter: DeckSelection?

    /// A label for the menu item, e.g. "Undo Apply Layout".
    let name: String

    init(before: [Slide], after: [Slide],
         themeBefore: SlideTheme? = nil, themeAfter: SlideTheme? = nil,
         masterBefore: SlideMaster? = nil, masterAfter: SlideMaster? = nil,
         selectionBefore: DeckSelection?, selectionAfter: DeckSelection?,
         name: String) {
        self.before = before
        self.after = after
        self.themeBefore = themeBefore
        self.themeAfter = themeAfter
        self.masterBefore = masterBefore
        self.masterAfter = masterAfter
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
        self.name = name
    }

    /// Whether this edit carries a theme change, as opposed to carrying no theme at all. A theme is
    /// optional on both sides, so "nil" cannot be read as "no change" without this.
    var changesTheme: Bool { themeBefore != nil || themeAfter != nil }

    /// The same, for the master — which really can go from absent to present, since a deck written
    /// before the master existed has none.
    var changesMaster: Bool { masterBefore != nil || masterAfter != nil }
}

// MARK: - EditHistory

/// Epic 7 — "Undo / redo".
///
/// A plain pair of stacks, capped at the web app's `MAX_HISTORY`. Recording a new edit clears the
/// redo stack, which is the rule every editor follows: once you have changed the future, the old
/// one is not reachable any more.
struct EditHistory {

    /// The web app keeps 100 steps; matching it means the two clients forget at the same depth.
    static let limit = 100

    private(set) var undoStack: [DeckEdit] = []
    private(set) var redoStack: [DeckEdit] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// The name of the edit undo would reverse, for the menu item.
    var undoName: String? { undoStack.last?.name }
    var redoName: String? { redoStack.last?.name }

    /// Files an edit that has already been applied.
    mutating func record(_ edit: DeckEdit) {
        undoStack.append(edit)
        if undoStack.count > Self.limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Moves one edit onto the redo stack and hands it back. The caller applies its "before" side.
    mutating func undo() -> DeckEdit? {
        guard let edit = undoStack.popLast() else { return nil }
        redoStack.append(edit)
        return edit
    }

    /// The inverse. The caller applies the returned edit's "after" side.
    mutating func redo() -> DeckEdit? {
        guard let edit = redoStack.popLast() else { return nil }
        undoStack.append(edit)
        return edit
    }

    /// Throws the history away — after a reload, when the slides it refers to are no longer the
    /// ones on screen.
    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
