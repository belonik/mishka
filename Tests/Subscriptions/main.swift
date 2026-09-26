import Combine
import Foundation

// SwiftUI only redraws when an object it observes publishes. The views observe `AppState`,
// while the note data lives in `NoteStore`, so every mutation on the store has to be
// republished by `AppState`. When that link is missing the model changes but the interface
// stays frozen — clicking a note in the list looks like it does nothing at all.

let checks = Checks("Store changes reach the interface")

let sandbox = URL(fileURLWithPath: "/tmp/mishka-tests/subscriptions-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: sandbox) }

let store = NoteStore(rootURL: sandbox)
let state = AppState(store: store)

var publications = 0
let subscription = state.objectWillChange.sink { publications += 1 }
defer { subscription.cancel() }

store.createNote(initialText: "# Первая\n\nтекст")
store.createNote(initialText: "# Вторая\n\nтекст")

checks.that("the fixture has notes to work with", store.activeNotes.count >= 2)
let first = store.activeNotes.first!

func expectRepublish(_ label: String, _ action: () -> Void) {
    let before = publications
    action()
    checks.that(label, publications > before, "nothing was published to the views")
}

// Selecting a note is what a click in the list does.
expectRepublish("selecting a note republishes") {
    store.selectedNoteID = first.id
}
expectRepublish("toggling a pin republishes") { store.togglePinned(id: first.id) }
expectRepublish("editing the text republishes") {
    store.update(id: first.id, text: "# Первая\n\nизменено")
}
expectRepublish("locking republishes") { store.setLocked(true, id: first.id) }
expectRepublish("a new note republishes") { store.createNote(initialText: "# Третья") }
expectRepublish("trashing republishes") { store.moveToTrash(id: first.id) }
expectRepublish("restoring republishes") { store.restore(id: first.id) }
expectRepublish("deleting permanently republishes") { store.deletePermanently(id: first.id) }
expectRepublish("opening a file in place republishes") {
    let url = sandbox.appendingPathComponent("external.md")
    try? "# Внешний\n\nтекст".write(to: url, atomically: true, encoding: .utf8)
    _ = store.openExternalFile(url)
}
expectRepublish("forgetting a file republishes") {
    store.forget(id: store.externalNotes.first!.id)
}

// The note list and the editor read the same source of truth.
let second = store.createNote(initialText: "# Выбранная")
store.selectedNoteID = second.id
checks.equal("AppState reports the selected note", state.selectedNote?.id, second.id)
checks.that("the selected note is in the visible list",
            state.visibleNotes.contains { $0.id == second.id })

checks.finish()
