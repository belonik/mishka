import Foundation

// Files opened in place: the app must edit the original file, never copy it, and it must
// keep remembering the file across restarts.

let checks = Checks("Files opened in place")

let sandbox = URL(fileURLWithPath: "/tmp/mishka-tests/store-\(UUID().uuidString)", isDirectory: true)
let vault = sandbox.appendingPathComponent("vault", isDirectory: true)
let outside = sandbox.appendingPathComponent("outside", isDirectory: true)
let fm = FileManager.default
try? fm.createDirectory(at: outside, withIntermediateDirectories: true)

let report = outside.appendingPathComponent("Report.md")
let original = "# Квартальный отчёт\n\nЖивёт в git-репозитории.\n"
try! original.write(to: report, atomically: true, encoding: .utf8)

let store = NoteStore(rootURL: vault)
checks.that("a fresh vault has no bound files", store.externalNotes.isEmpty)

let note = store.openExternalFile(report)
checks.that("the file opens", note != nil)
checks.that("it is marked as external", note?.isExternal == true)
checks.equal("the path is remembered", note?.externalPath ?? "", report.path)
checks.equal("the text is read from disk", note?.text ?? "", original)
checks.equal("the title is derived", note?.title ?? "", "Квартальный отчёт")

// Editing must reach the original and must not leave a copy behind.
store.update(id: note!.id, text: "# Квартальный отчёт\n\nОтредактировано в Mishka.\n")
store.flush()
checks.that("the original file is edited in place",
            (try? String(contentsOf: report, encoding: .utf8))?.contains("Отредактировано в Mishka") == true)

let vaultNotes = vault.appendingPathComponent("notes")
let vaultFiles = (try? fm.contentsOfDirectory(atPath: vaultNotes.path)) ?? []
let leaked = vaultFiles
    .map { (try? String(contentsOf: vaultNotes.appendingPathComponent($0), encoding: .utf8)) ?? "" }
    .filter { $0.contains("Отредактировано в Mishka") }
checks.that("no copy is created in the vault", leaked.isEmpty,
            "vault/notes holds \(vaultFiles.count) file(s)")

_ = store.openExternalFile(report)
checks.equal("re-opening does not duplicate the entry", store.externalNotes.count, 1)

// The history entry must survive a restart. The store writes the index on a background
// queue, so wait for it before opening a second store on the same vault — otherwise the
// check races the write and passes or fails depending on machine speed.
store.flush()
let reopened = NoteStore(rootURL: vault)
checks.equal("the history survives a restart", reopened.externalNotes.count, 1)
checks.equal("still bound to the same path", reopened.externalNotes.first?.externalPath ?? "", report.path)
checks.that("externalPath is persisted in library.json",
            ((try? String(contentsOf: vault.appendingPathComponent("library.json"), encoding: .utf8)) ?? "")
                .contains("externalPath"))

// Mishka must never delete or trash a file it does not own.
reopened.moveToTrash(id: reopened.externalNotes.first!.id)
checks.that("trash forgets the entry instead", reopened.externalNotes.isEmpty)
checks.that("the file survives being trashed", fm.fileExists(atPath: report.path))

// A file that disappears keeps its place in the history and is flagged.
_ = reopened.openExternalFile(report)
try? fm.removeItem(at: report)
reopened.refreshExternalNotes()
checks.that("a missing file is flagged", reopened.externalNotes.first?.isMissing == true)

reopened.flush()
let afterMissing = NoteStore(rootURL: vault)
checks.equal("a missing file keeps its history entry", afterMissing.externalNotes.count, 1)
checks.that("still flagged after a restart", afterMissing.externalNotes.first?.isMissing == true)

try! "# Вернулся\n\nснова тут\n".write(to: report, atomically: true, encoding: .utf8)
afterMissing.refreshExternalNotes()
checks.that("it recovers when the file returns", afterMissing.externalNotes.first?.isMissing == false)
checks.that("the new content is re-read",
            afterMissing.externalNotes.first?.text.contains("Вернулся") == true)

// A file that already lives in the vault must not be tracked twice.
let vaultNoteCount = afterMissing.activeNotes.filter { !$0.isExternal }.count
let firstVaultNote = afterMissing.activeNotes.first { !$0.isExternal }!
_ = afterMissing.openExternalFile(afterMissing.fileURL(for: firstVaultNote))
checks.equal("opening a vault file does not duplicate it",
             afterMissing.activeNotes.filter { !$0.isExternal }.count, vaultNoteCount)
checks.that("it stays a vault note", afterMissing.note(id: firstVaultNote.id)?.isExternal == false)

// Copying into the library stays an explicit action.
afterMissing.importMarkdownFiles([report])
afterMissing.flush()
checks.that("explicit import still copies into the library",
            ((try? fm.contentsOfDirectory(atPath: vaultNotes.path)) ?? []).count > 0)

try? fm.removeItem(at: sandbox)
checks.finish()
