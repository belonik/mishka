import Foundation
import SwiftUI

// MARK: - Sorting

enum SortField: String, CaseIterable, Identifiable, Codable {
    case modified
    case created
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .modified: return "Date Modified"
        case .created: return "Date Created"
        case .title: return "Title"
        }
    }
}

struct SortOrder: Equatable, Codable {
    var field: SortField = .modified
    var ascending: Bool = false

    var label: String { "\(field.label) \(ascending ? "↑" : "↓")" }
}

// MARK: - Sidebar selection

enum SidebarItem: Hashable {
    case all
    case pinned
    /// Notes bound to files outside the vault, edited where they live.
    case files
    case untagged
    case todo
    case today
    case locked
    case trash
    case tag(String)

    var isSpecial: Bool {
        if case .tag = self { return false }
        return true
    }
}

// MARK: - Debouncer

/// Runs the last scheduled block after `delay` seconds of silence.
final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func schedule(_ delay: TimeInterval = 0.6, _ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }

    func flush() {
        guard let item = workItem, !item.isCancelled else { return }
        workItem = nil
        item.perform()
    }
}

// MARK: - Date formatting

enum DateFormat {
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Bear-style compact stamp for the note list: "14:32", "Yesterday", "3 Mar", "3 Mar 2024".
    static func short(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) { return dayMonth.string(from: date) }
        return dayMonth.string(from: date) + " " + String(cal.component(.year, from: date))
    }

    static func long(_ date: Date) -> String { full.string(from: date) }

    /// "just now", "5 minutes ago", "3 days ago" …
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - String helpers

/// `---`, `***` or `___` on a line of its own: a thematic break, never a title.
private func isThematicBreakLine(_ line: String) -> Bool {
    let stripped = line.filter { !$0.isWhitespace }
    guard stripped.count >= 3, let first = stripped.first,
          first == "-" || first == "*" || first == "_" else { return false }
    return stripped.allSatisfy { $0 == first }
}

extension String {
    /// Index of the first line that carries actual note content. A leading YAML
    /// front-matter block (`---` … `---`) is metadata, not the note itself, so notes
    /// written by other tools still get a sensible title.
    var noteBodyStartIndex: Int {
        let lines = split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        for index in 1..<max(1, lines.count) {
            let marker = lines[index].trimmingCharacters(in: .whitespaces)
            if marker == "---" || marker == "..." { return index + 1 }
        }
        return 0
    }

    /// First non-empty line of the body, with a leading heading marker and trailing hashes removed.
    var noteTitle: String {
        let lines = split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start = noteBodyStartIndex
        for rawLine in lines.dropFirst(start) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !isThematicBreakLine(line) else { continue }
            var title = line
            // Strip leading '#' characters (ATX heading) plus following spaces.
            while title.hasPrefix("#") { title.removeFirst() }
            title = title.trimmingCharacters(in: .whitespaces)
            // Strip a trailing closing sequence, e.g. "## Title ##"
            while title.hasSuffix("#") { title.removeLast() }
            title = title.trimmingCharacters(in: .whitespaces)
            title = title.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "==", with: "")
                .replacingOccurrences(of: "`", with: "")
            return title.isEmpty ? "Untitled" : title
        }
        return "Untitled"
    }

    /// Plain-text snippet for the note list: markdown syntax removed, whitespace collapsed.
    func plainSnippet(limit: Int = 220) -> String {
        var out = ""
        var inFence = false
        let lines = split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let bodyStart = noteBodyStartIndex
        var sawTitle = false
        for (index, raw) in lines.enumerated() {
            if index < bodyStart { continue } // front matter is not part of the snippet
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if trimmed.isEmpty { continue }
            if isThematicBreakLine(trimmed) { continue }
            // Table rows read as noise in a one-line snippet.
            if trimmed.hasPrefix("|") {
                if trimmed.contains("-"), trimmed.allSatisfy({ "|-: ".contains($0) }) { continue }
                out += trimmed.replacingOccurrences(of: "|", with: " ") + " "
                if out.count > limit { break }
                continue
            }
            if !sawTitle {
                sawTitle = true
                continue // the title line itself
            }
            var line = trimmed
            if line.hasPrefix("> ") { line.removeFirst(2) }
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespaces)
            for marker in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ "] where line.hasPrefix(marker) {
                line.removeFirst(marker.count)
                break
            }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "==", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "~~", with: "")
            out += line + " "
            if out.count > limit { break }
        }
        let collapsed = out.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var characterCount: Int { count }

    /// ~200 words per minute, never below one minute for non-empty text.
    var readingMinutes: Int {
        let words = wordCount
        if words == 0 { return 0 }
        return max(1, Int((Double(words) / 200.0).rounded(.up)))
    }
}

// MARK: - Small view helpers

extension View {
    /// Applies a transform only when the condition holds.
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }

    /// A hairline separator that matches the current theme.
    func hairline(_ color: Color, axis: Axis = .horizontal, thickness: CGFloat = 1) -> some View {
        overlay(
            Rectangle()
                .fill(color)
                .frame(
                    width: axis == .vertical ? thickness : nil,
                    height: axis == .horizontal ? thickness : nil
                ),
            alignment: axis == .vertical ? .trailing : .bottom
        )
    }
}

/// A 1-point separator the user can drag to resize the surrounding columns.
struct ResizableDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    let color: Color
    var inverted: Bool = false

    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: 9)
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let base = startWidth ?? width
                                if startWidth == nil { startWidth = base }
                                let delta = inverted ? -value.translation.width : value.translation.width
                                width = min(range.upperBound, max(range.lowerBound, base + delta))
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            )
    }
}
