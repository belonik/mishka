import AppKit
import Foundation

// MARK: - Typography

enum EditorFontFamily: String, CaseIterable, Identifiable, Codable {
    case system
    case rounded
    case serif
    case charter
    case avenir
    case mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .charter: return "Charter"
        case .avenir: return "Avenir Next"
        case .mono: return "Mono"
        }
    }

    /// CSS fragment handed to the WebKit preview so both panes match.
    var cssFamily: String {
        switch self {
        case .system: return "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", system-ui, sans-serif"
        case .rounded: return "\"SF Pro Rounded\", ui-rounded, -apple-system, sans-serif"
        case .serif: return "\"New York\", ui-serif, Georgia, \"Iowan Old Style\", serif"
        case .charter: return "Charter, \"Bitstream Charter\", Georgia, serif"
        case .avenir: return "\"Avenir Next\", Avenir, \"Helvetica Neue\", sans-serif"
        case .mono: return "\"SF Mono\", ui-monospace, Menlo, monospace"
        }
    }

    /// Real PostScript families used for the AppKit text view. `nil` means "use the
    /// system font descriptor with a design".
    var familyName: String? {
        switch self {
        case .system, .rounded, .serif, .mono: return nil
        case .charter: return "Charter"
        case .avenir: return "Avenir Next"
        }
    }

    var design: NSFontDescriptor.SystemDesign? {
        switch self {
        case .system, .charter, .avenir: return nil
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

struct EditorTypography: Equatable {
    var family: EditorFontFamily = .system
    var size: CGFloat = 15
    var lineSpacing: CGFloat = 4.5
    var paragraphSpacing: CGFloat = 9

    func baseFont() -> NSFont {
        EditorTypography.font(family: family, size: size, weight: .regular, italic: false)
    }

    static func font(
        family: EditorFontFamily,
        size: CGFloat,
        weight: NSFont.Weight,
        italic: Bool
    ) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        let isBold = weight.rawValue >= NSFont.Weight.semibold.rawValue
        if isBold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }

        if let familyName = family.familyName {
            let descriptor = NSFontDescriptor(fontAttributes: [.family: familyName])
                .withSymbolicTraits(traits)
            if let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
        }

        var base = NSFont.systemFont(ofSize: size, weight: weight)
        if let design = family.design,
           let descriptor = base.fontDescriptor.withDesign(design) {
            base = NSFont(descriptor: descriptor, size: size) ?? base
        }
        if traits.contains(.italic) {
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            base = NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }
}

// MARK: - Custom attributes understood by the layout manager

extension NSAttributedString.Key {
    /// `NSNumber` — 1 when the line starts with a checked `- [x]` task, 0 when open.
    static let mishkaTask = NSAttributedString.Key("app.mishka.task")
    /// `NSNumber` — nesting level of an unordered list item (the bullet is drawn in the gutter).
    static let mishkaBullet = NSAttributedString.Key("app.mishka.bullet")
    /// `NSNumber` — nesting level of the paragraph, used for gutter geometry.
    static let mishkaIndent = NSAttributedString.Key("app.mishka.indent")
    /// `NSNumber` — 1 for syntax markers, 1 = hidden, 0 = visible (dimmed).
    static let mishkaMarker = NSAttributedString.Key("app.mishka.marker")
    /// `NSNumber` — character offset of the marker within its paragraph (task index hint).
    static let mishkaParagraphStart = NSAttributedString.Key("app.mishka.paragraphStart")
    /// `NSNumber` — table row kind: 0 header, 1 delimiter, 2 body. Drives the gutter drawing.
    static let mishkaTableRole = NSAttributedString.Key("app.mishka.tableRole")
    /// `NSNumber` — index of the row inside its table.
    static let mishkaTableRow = NSAttributedString.Key("app.mishka.tableRow")
    /// `NSValue(range:)` — the whole table, repeated on every one of its lines.
    static let mishkaTableBlock = NSAttributedString.Key("app.mishka.tableBlock")
    /// `NSNumber` — 1 on the final line of a table.
    static let mishkaTableLast = NSAttributedString.Key("app.mishka.tableLast")
}

// MARK: - Highlighter

/// Renders markdown *as you type* — the signature Bear behaviour. Everything is a pure
/// attribute pass over an `NSTextStorage`; the underlying characters are never modified,
/// so the file on disk always stays plain markdown.
final class MarkdownHighlighter {

    var typography: EditorTypography {
        didSet { if typography != oldValue { cachedFonts.removeAll() } }
    }
    var theme: Theme
    var accent: NSColor

    private var cachedFonts: [String: NSFont] = [:]

    init(typography: EditorTypography, theme: Theme, accent: NSColor) {
        self.typography = typography
        self.theme = theme
        self.accent = accent
    }

    // MARK: Fonts

    private func font(_ weight: NSFont.Weight, italic: Bool = false, scale: CGFloat = 1) -> NSFont {
        let size = (typography.size * scale).rounded()
        let key = "\(weight.rawValue)-\(italic)-\(size)"
        if let cached = cachedFonts[key] { return cached }
        let font = EditorTypography.font(family: typography.family, size: size, weight: weight, italic: italic)
        cachedFonts[key] = font
        return font
    }

    private var bodyFont: NSFont { font(.regular) }
    private var boldFont: NSFont { font(.bold) }
    private var italicFont: NSFont { font(.regular, italic: true) }
    private var boldItalicFont: NSFont { font(.bold, italic: true) }
    private var monoFont: NSFont {
        EditorTypography.font(family: .mono, size: (typography.size * 0.94).rounded(), weight: .regular, italic: false)
    }

    // MARK: Colours

    private var textColor: NSColor { NSColor(hex: theme.text) }
    private var secondaryColor: NSColor { NSColor(hex: theme.secondaryText) }
    private var tertiaryColor: NSColor { NSColor(hex: theme.tertiaryText) }
    private var markerColor: NSColor { NSColor(hex: theme.marker) }
    private var headingColor: NSColor { NSColor(hex: theme.heading) }
    private var linkColor: NSColor { accent }
    private var tagColor: NSColor { NSColor(hex: theme.tag) }
    private var quoteColor: NSColor { NSColor(hex: theme.quote) }
    private var codeColor: NSColor { NSColor(hex: theme.codeText) }
    private var codeBackground: NSColor { NSColor(hex: theme.codeBackground) }

    /// Font used for characters that should be invisible but still occupy (almost) no width.
    private static let hiddenFont = NSFont.systemFont(ofSize: 0.1)

    // MARK: - Main entry point

    /// Re-applies every attribute. `selection` decides which syntax markers are revealed:
    /// markers on the paragraph that currently holds the caret stay visible (dimmed) so the
    /// user can edit them, every other paragraph hides them behind the rendered text.
    func highlight(_ storage: NSTextStorage, selection: NSRange) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        guard full.length > 0 else { return }

        let caret = NSRange(location: min(max(0, selection.location), full.length), length: 0)
        let revealParagraph = text.paragraphRange(for: caret)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: full)

        var protected: [NSRange] = []
        let structure = scanStructure(text, storage: storage, revealParagraph: revealParagraph, protected: &protected)
        scanInline(
            text,
            storage: storage,
            revealParagraph: revealParagraph,
            structure: structure,
            protected: &protected
        )

        storage.endEditing()
    }

    /// Dims everything outside `paragraph`, Bear's focused mode.
    func applyFocusDim(_ storage: NSTextStorage, keeping paragraph: NSRange) {
        let length = storage.length
        guard length > 0 else { return }
        let dim = NSColor(hex: theme.text).blended(with: NSColor(hex: theme.background), amount: 0.66)
        let ranges = [
            NSRange(location: 0, length: max(0, min(paragraph.location, length))),
            NSRange(
                location: min(NSMaxRange(paragraph), length),
                length: max(0, length - min(NSMaxRange(paragraph), length))
            ),
        ]
        storage.beginEditing()
        for range in ranges where range.length > 0 {
            storage.addAttribute(.foregroundColor, value: dim, range: range)
        }
        storage.endEditing()
    }

    /// Marker styling: hidden (zero-width) or revealed as a quiet grey.
    private func markerAttributes(hidden: Bool) -> [NSAttributedString.Key: Any] {
        if hidden {
            return [
                .font: MarkdownHighlighter.hiddenFont,
                .foregroundColor: NSColor.clear,
                .mishkaMarker: 1,
            ]
        }
        return [
            .font: font(.regular),
            .foregroundColor: markerColor,
            .mishkaMarker: 0,
        ]
    }

    private func hide(_ range: NSRange, in storage: NSTextStorage, revealParagraph: NSRange) {
        guard range.length > 0 else { return }
        let hidden = NSIntersectionRange(range, revealParagraph).length == 0
        storage.addAttributes(markerAttributes(hidden: hidden), range: range)
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = typography.lineSpacing
        paragraph.paragraphSpacing = typography.paragraphSpacing
        paragraph.minimumLineHeight = (typography.size * 1.28).rounded()
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
            .mishkaIndent: 0,
            .ligature: 1,
        ]
    }

    // MARK: - Block level scanning

    private struct Structure {
        /// Ranges of fenced code blocks, including the fences.
        var codeBlocks: [NSRange] = []
        /// Paragraph ranges that are inside a fenced code block.
        var codeLines: [NSRange] = []
        /// Paragraph ranges belonging to a list item.
        var listParagraphs: [NSRange] = []
        /// Inline `#tag` ranges outside of code.
        var tagRanges: [NSRange] = []
        /// Character ranges of complete GFM tables.
        var tableBlocks: [NSRange] = []
        /// The leading YAML front-matter block, when the note has one.
        var frontMatter: NSRange?
    }

    @discardableResult
    private func scanStructure(
        _ text: NSString,
        storage: NSTextStorage,
        revealParagraph: NSRange,
        protected: inout [NSRange]
    ) -> Structure {
        var structure = Structure()
        var location = 0
        var inFence = false
        var fenceStart = 0
        var fenceMarker = ""

        // A leading YAML front-matter block is metadata, so it gets its own compact
        // treatment instead of five loose paragraphs at the top of every note.
        if let frontMatterEnd = MarkdownHighlighter.frontMatterEnd(in: text) {
            let block = NSRange(location: 0, length: frontMatterEnd)
            applyFrontMatter(storage, block: block)
            protected.append(block)
            structure.frontMatter = block
            location = frontMatterEnd
        }

        // GFM table state: a table runs from its header row until the first line
        // that is not a row.
        var inTable = false
        var tableRowIndex = 0
        var tableLineRanges: [NSRange] = []

        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let contentLength = max(0, lineRange.length - (line.hasSuffix("\n") ? 1 : 0))

            if !inFence, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = true
                fenceStart = lineRange.location
                fenceMarker = String(trimmed.prefix(3))
                applyFenceLine(storage, lineRange: lineRange, contentRange: NSRange(location: lineRange.location, length: contentLength))
                location = NSMaxRange(lineRange)
                continue
            }
            if inFence {
                if trimmed.hasPrefix(fenceMarker) {
                    applyFenceLine(storage, lineRange: lineRange, contentRange: NSRange(location: lineRange.location, length: contentLength))
                    let blockRange = NSRange(location: fenceStart, length: NSMaxRange(lineRange) - fenceStart)
                    structure.codeBlocks.append(blockRange)
                    protected.append(blockRange)
                    inFence = false
                } else {
                    let range = NSRange(location: lineRange.location, length: contentLength)
                    storage.addAttributes([
                        .font: monoFont,
                        .foregroundColor: codeColor,
                    ], range: range)
                    storage.addAttribute(.backgroundColor, value: codeBackground, range: range)
                    structure.codeLines.append(lineRange)
                    protected.append(range)
                }
                location = NSMaxRange(lineRange)
                continue
            }

            // Not in a fence: classify the line.
            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            let content = contentLength > 0 ? text.substring(with: contentRange) : ""
            if contentLength > 0 {
                structure.tagRanges.append(contentsOf: MarkdownHighlighter.tagRanges(in: text, range: contentRange))
            }

            var handledAsTable = false
            if inTable {
                if contentLength > 0, MarkdownHighlighter.isTableRow(content) {
                    tableRowIndex += 1
                    let isDelimiter = tableRowIndex == 1 && MarkdownHighlighter.isTableDelimiter(content)
                    applyTableLine(
                        storage,
                        role: isDelimiter ? 1 : 2,
                        rowIndex: tableRowIndex,
                        content: content,
                        contentRange: contentRange,
                        revealParagraph: revealParagraph
                    )
                    tableLineRanges.append(contentRange)
                    handledAsTable = true
                } else {
                    closeTable(storage, lineRanges: tableLineRanges, structure: &structure)
                    inTable = false
                    tableLineRanges = []
                }
            } else if contentLength > 0, MarkdownHighlighter.isTableRow(content) {
                // A header row is only a table if the very next line is a delimiter row.
                let nextStart = NSMaxRange(lineRange)
                if nextStart < text.length {
                    let nextLineRange = text.lineRange(for: NSRange(location: nextStart, length: 0))
                    let nextString = text.substring(with: nextLineRange)
                    let nextLength = max(0, nextLineRange.length - (nextString.hasSuffix("\n") ? 1 : 0))
                    let nextContent = nextLength > 0
                        ? text.substring(with: NSRange(location: nextLineRange.location, length: nextLength))
                        : ""
                    if MarkdownHighlighter.isTableDelimiter(nextContent) {
                        inTable = true
                        tableRowIndex = 0
                        tableLineRanges = [contentRange]
                        applyTableLine(
                            storage,
                            role: 0,
                            rowIndex: 0,
                            content: content,
                            contentRange: contentRange,
                            revealParagraph: revealParagraph
                        )
                        handledAsTable = true
                    }
                }
            }

            if !handledAsTable {
                classifyLine(text, lineRange: lineRange, contentLength: contentLength, storage: storage, revealParagraph: revealParagraph, structure: &structure, protected: &protected)
            }
            location = NSMaxRange(lineRange)
        }

        if inTable {
            closeTable(storage, lineRanges: tableLineRanges, structure: &structure)
        }

        // An unterminated fence still deserves code styling.
        if inFence, fenceStart < text.length {
            let blockRange = NSRange(location: fenceStart, length: text.length - fenceStart)
            structure.codeBlocks.append(blockRange)
            protected.append(blockRange)
        }
        return structure
    }

    // MARK: - Front matter

    /// End offset of a leading YAML front-matter block, or `nil` when the note does not
    /// start with one. Only `key: value` lines count, so a note that merely begins with a
    /// thematic break is left alone.
    static func frontMatterEnd(in text: NSString) -> Int? {
        guard text.length > 3 else { return nil }
        let firstRange = text.lineRange(for: NSRange(location: 0, length: 0))
        let first = text.substring(with: firstRange).trimmingCharacters(in: .whitespacesAndNewlines)
        guard first == "---" else { return nil }

        var location = NSMaxRange(firstRange)
        var sawPair = false
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let marker = text.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if marker == "---" || marker == "..." {
                return sawPair ? NSMaxRange(lineRange) : nil
            }
            if marker.isEmpty {
                location = NSMaxRange(lineRange)
                continue
            }
            guard marker.contains(":") else { return nil }
            sawPair = true
            location = NSMaxRange(lineRange)
        }
        return nil
    }

    private func applyFrontMatter(_ storage: NSTextStorage, block: NSRange) {
        let text = storage.string as NSString
        let tint = NSColor(hex: theme.background).blended(with: NSColor(hex: theme.border), amount: 0.55)

        var location = block.location
        let end = NSMaxRange(block)
        while location < end {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let raw = text.substring(with: lineRange)
            let contentLength = max(0, lineRange.length - (raw.hasSuffix("\n") ? 1 : 0))
            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            let content = text.substring(with: contentRange)
            let trimmed = content.trimmingCharacters(in: .whitespaces)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 1
            paragraph.paragraphSpacing = 0
            paragraph.minimumLineHeight = (typography.size * 1.2).rounded()
            paragraph.firstLineHeadIndent = 9
            paragraph.headIndent = 9

            storage.addAttributes([
                .paragraphStyle: paragraph,
                .backgroundColor: tint,
                .font: font(.regular, scale: 0.9),
            ], range: contentRange)

            if trimmed == "---" || trimmed == "..." || trimmed.isEmpty {
                storage.addAttribute(.foregroundColor, value: markerColor, range: contentRange)
            } else {
                let nsContent = content as NSString
                let colon = nsContent.range(of: ":")
                if colon.location != NSNotFound {
                    let keyLength = colon.location + colon.length
                    storage.addAttribute(
                        .foregroundColor,
                        value: secondaryColor,
                        range: NSRange(location: contentRange.location, length: keyLength)
                    )
                    let valueRange = NSRange(
                        location: contentRange.location + keyLength,
                        length: max(0, contentRange.length - keyLength)
                    )
                    if valueRange.length > 0 {
                        storage.addAttribute(.foregroundColor, value: tertiaryColor, range: valueRange)
                    }
                } else {
                    storage.addAttribute(.foregroundColor, value: secondaryColor, range: contentRange)
                }
            }
            location = NSMaxRange(lineRange)
        }
    }

    // MARK: - Tables

    /// Horizontal inset of table cells from the edge of the drawn card.
    static let tableInset: CGFloat = 9

    /// A line belongs to a table when it carries at least one cell separator.
    static func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    /// `|---|:---:|---|` — the row that turns the line above it into a header.
    static func isTableDelimiter(_ line: String) -> Bool {
        var core = line.trimmingCharacters(in: .whitespaces)
        guard core.contains("-") else { return false }
        if core.hasPrefix("|") { core.removeFirst() }
        if core.hasSuffix("|") { core.removeLast() }
        let cells = core.split(separator: "|", omittingEmptySubsequences: false)
        guard !cells.isEmpty else { return false }
        for cell in cells {
            var body = cell.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return false }
            if body.hasPrefix(":") { body.removeFirst() }
            if body.hasSuffix(":") { body.removeLast() }
            guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else { return false }
        }
        return true
    }

    /// Styles one line of a table. The header is emphasised, the delimiter row collapses
    /// into a hairline (the layout manager draws it), and the pipes fade into the
    /// background so the cell text reads as cells rather than as source code.
    private func applyTableLine(
        _ storage: NSTextStorage,
        role: Int,
        rowIndex: Int,
        content: String,
        contentRange: NSRange,
        revealParagraph: NSRange
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = typography.lineSpacing
        paragraph.paragraphSpacing = 0
        paragraph.minimumLineHeight = (typography.size * 1.28).rounded()
        // The card is drawn around the table, so the cells are inset from its edge.
        paragraph.firstLineHeadIndent = MarkdownHighlighter.tableInset
        paragraph.headIndent = MarkdownHighlighter.tableInset

        if role == 1 {
            let reveal = NSIntersectionRange(contentRange, revealParagraph).length > 0
            if reveal {
                storage.addAttributes([
                    .font: monoFont,
                    .foregroundColor: markerColor,
                    .paragraphStyle: paragraph,
                    .mishkaMarker: 0,
                ], range: contentRange)
            } else {
                // Collapse the row to a thin gap; the rule is drawn underneath it.
                paragraph.minimumLineHeight = 5
                paragraph.maximumLineHeight = 5
                storage.addAttributes([
                    .font: MarkdownHighlighter.hiddenFont,
                    .foregroundColor: NSColor.clear,
                    .paragraphStyle: paragraph,
                    .mishkaMarker: 1,
                ], range: contentRange)
            }
        } else {
            var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph]
            if role == 0 {
                attributes[.font] = font(.semibold, scale: 0.99)
                attributes[.foregroundColor] = headingColor
            }
            // A whisper of zebra striping so wide tables stay readable.
            if role >= 2, rowIndex % 2 == 0 {
                attributes[.backgroundColor] = NSColor(hex: theme.text)
                    .withAlphaComponent(theme.isDark ? 0.026 : 0.02)
            }
            storage.addAttributes(attributes, range: contentRange)
        }

        storage.addAttributes([
            .mishkaTableRole: role,
            .mishkaTableRow: rowIndex,
        ], range: contentRange)

        // Quiet the pipe characters.
        if role != 1 {
            let line = content as NSString
            for index in 0..<line.length where line.character(at: index) == 0x7C {
                storage.addAttribute(
                    .foregroundColor,
                    value: markerColor,
                    range: NSRange(location: contentRange.location + index, length: 1)
                )
            }
        }
    }

    /// Records the extent of a finished table so the layout manager can draw its card.
    private func closeTable(_ storage: NSTextStorage, lineRanges: [NSRange], structure: inout Structure) {
        guard let first = lineRanges.first, let last = lineRanges.last else { return }
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        storage.addAttribute(.mishkaTableBlock, value: NSValue(range: block), range: block)
        storage.addAttribute(.mishkaTableLast, value: 1, range: last)
        structure.tableBlocks.append(block)
    }

    private func applyFenceLine(_ storage: NSTextStorage, lineRange: NSRange, contentRange: NSRange) {
        storage.addAttributes([
            .font: monoFont,
            .foregroundColor: tertiaryColor,
            .backgroundColor: codeBackground,
        ], range: contentRange)
        _ = lineRange
    }

    private func classifyLine(
        _ text: NSString,
        lineRange: NSRange,
        contentLength: Int,
        storage: NSTextStorage,
        revealParagraph: NSRange,
        structure: inout Structure,
        protected: inout [NSRange]
    ) {
        let contentRange = NSRange(location: lineRange.location, length: contentLength)
        guard contentLength > 0 else { return }
        let line = text.substring(with: contentRange)
        let trimmedLeading = line.drop(while: { $0 == " " || $0 == "\t" })
        let indentSpaces = line.count - trimmedLeading.count

        // Horizontal rule
        if Self.isHorizontalRule(String(trimmedLeading)) {
            storage.addAttributes([
                .foregroundColor: markerColor,
                .font: font(.regular),
            ], range: contentRange)
            return
        }

        // Heading
        let trimmedNSString = text.substring(with: NSRange(location: contentRange.location + indentSpaces, length: contentRange.length - indentSpaces)) as NSString
        if let heading = matchHeading(trimmedNSString) {
            applyHeading(
                storage,
                contentRange: contentRange,
                indentSpaces: indentSpaces,
                level: heading.level,
                hashes: heading.hashes,
                trailing: heading.trailing,
                revealParagraph: revealParagraph,
                protected: &protected
            )
            return
        }

        // Blockquote
        var quoteDepth = 0
        var rest = String(trimmedLeading)
        var consumed = indentSpaces
        while rest.hasPrefix(">") {
            quoteDepth += 1
            rest.removeFirst()
            consumed += 1
            if rest.hasPrefix(" ") { rest.removeFirst(); consumed += 1 }
        }
        if quoteDepth > 0 {
            let markerRange = NSRange(location: contentRange.location + indentSpaces, length: consumed - indentSpaces)
            storage.addAttributes([
                .foregroundColor: quoteColor,
                .font: font(.semibold),
            ], range: markerRange)
            protected.append(markerRange)
            let paragraph = paragraphStyle(indent: quoteDepth, extraFirstLine: 0)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: contentRange)
            storage.addAttribute(.mishkaIndent, value: quoteDepth, range: contentRange)
            if rest.isEmpty { return }
            // Continue to list detection on the remaining text by shifting the window.
            let shifted = NSRange(location: contentRange.location + consumed, length: contentRange.length - consumed)
            classifyListOrText(text, range: shifted, indentSpaces: consumed, storage: storage, structure: &structure, protected: &protected)
            return
        }

        classifyListOrText(text, range: contentRange, indentSpaces: indentSpaces, storage: storage, structure: &structure, protected: &protected)
    }

    private func classifyListOrText(
        _ text: NSString,
        range: NSRange,
        indentSpaces: Int,
        storage: NSTextStorage,
        structure: inout Structure,
        protected: inout [NSRange]
    ) {
        let line = text.substring(with: range)
        let level = min(6, indentSpaces / 2)

        // Task list: `- [ ] text`
        if let task = Self.matchTask(line) {
            let checked = task.checked
            let markerRange = NSRange(location: range.location, length: task.markerLength)
            storage.addAttributes(markerAttributes(hidden: true), range: markerRange)
            protected.append(markerRange)

            let paragraph = paragraphStyle(indent: level + 1, extraFirstLine: 0)
            storage.addAttributes([
                .paragraphStyle: paragraph,
                .mishkaTask: checked ? 1 : 0,
                .mishkaIndent: level + 1,
                .mishkaParagraphStart: range.location,
            ], range: range)
            if checked {
                storage.addAttribute(.foregroundColor, value: secondaryColor, range: NSRange(location: NSMaxRange(markerRange), length: range.length - task.markerLength))
            }
            structure.listParagraphs.append(range)
            return
        }

        // Bullet list: `- text`
        if let bullet = Self.matchBullet(line) {
            let markerRange = NSRange(location: range.location, length: bullet.markerLength)
            storage.addAttributes(markerAttributes(hidden: true), range: markerRange)
            protected.append(markerRange)
            let paragraph = paragraphStyle(indent: level + 1, extraFirstLine: 0)
            storage.addAttributes([
                .paragraphStyle: paragraph,
                .mishkaBullet: level,
                .mishkaIndent: level + 1,
                .mishkaParagraphStart: range.location,
            ], range: range)
            structure.listParagraphs.append(range)
            return
        }

        // Ordered list: `1. text` — the number stays visible, dimmed.
        if let ordered = Self.matchOrdered(line) {
            let markerRange = NSRange(location: range.location, length: ordered.markerLength)
            storage.addAttributes([
                .font: font(.regular),
                .foregroundColor: markerColor,
                .mishkaMarker: 0,
            ], range: markerRange)
            protected.append(markerRange)
            let paragraph = paragraphStyle(indent: level + 1, extraFirstLine: 0)
            storage.addAttributes([
                .paragraphStyle: paragraph,
                .mishkaIndent: level + 1,
                .mishkaParagraphStart: range.location,
            ], range: range)
            structure.listParagraphs.append(range)
            return
        }

        if level > 0 {
            let paragraph = paragraphStyle(indent: level, extraFirstLine: 0)
            storage.addAttributes([
                .paragraphStyle: paragraph,
                .mishkaIndent: level,
            ], range: range)
        }
    }

    private func paragraphStyle(indent: Int, extraFirstLine: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        let step = (typography.size * 1.55).rounded()
        let leading = step * CGFloat(max(0, indent))
        paragraph.firstLineHeadIndent = leading + extraFirstLine
        paragraph.headIndent = leading + step * 0.0
        paragraph.lineSpacing = typography.lineSpacing
        paragraph.paragraphSpacing = typography.paragraphSpacing
        paragraph.minimumLineHeight = (typography.size * 1.28).rounded()
        return paragraph
    }

    // MARK: - Headings

    private struct HeadingMatch {
        var level: Int
        var hashes: NSRange      // relative to the string that was matched
        var trailing: NSRange?   // relative to the string that was matched
    }

    private func matchHeading(_ line: NSString) -> HeadingMatch? {
        let hashChar: unichar = 0x23      // '#'
        let spaceChar: unichar = 0x20
        let tabChar: unichar = 0x09

        func isSpace(_ c: unichar) -> Bool { c == spaceChar || c == tabChar }

        let length = line.length
        var index = 0
        while index < length, index < 7, line.character(at: index) == hashChar { index += 1 }
        let level = index
        guard level >= 1, level <= 6, index < length, isSpace(line.character(at: index)) else { return nil }
        while index < length, isSpace(line.character(at: index)) { index += 1 }
        let hashLength = index

        // Trailing closing sequence, e.g. "## Title ##"
        var trailing: NSRange?
        var end = length
        while end > index, isSpace(line.character(at: end - 1)) { end -= 1 }
        if end > index, line.character(at: end - 1) == hashChar {
            var hashStart = end
            var hashes = 0
            while hashStart > index, line.character(at: hashStart - 1) == hashChar {
                hashStart -= 1
                hashes += 1
            }
            if hashes > 0, hashStart > index, isSpace(line.character(at: hashStart - 1)) {
                trailing = NSRange(location: hashStart, length: length - hashStart)
            }
        }

        return HeadingMatch(
            level: level,
            hashes: NSRange(location: 0, length: hashLength),
            trailing: trailing
        )
    }

    private func applyHeading(
        _ storage: NSTextStorage,
        contentRange: NSRange,
        indentSpaces: Int,
        level: Int,
        hashes: NSRange,
        trailing: NSRange?,
        revealParagraph: NSRange,
        protected: inout [NSRange]
    ) {
        let scales: [CGFloat] = [1.95, 1.62, 1.36, 1.18, 1.06, 1.0]
        let scale = scales[min(level - 1, scales.count - 1)]
        let headingFont = font(level <= 2 ? .bold : .semibold, scale: scale)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = typography.lineSpacing
        paragraph.paragraphSpacing = typography.paragraphSpacing * (level == 1 ? 1.5 : 1.15)
        paragraph.paragraphSpacingBefore = typography.paragraphSpacing * (level == 1 ? 1.4 : 0.9)
        paragraph.minimumLineHeight = (typography.size * scale * 1.24).rounded()
        if indentSpaces > 0 {
            let step = (typography.size * 1.55).rounded()
            paragraph.firstLineHeadIndent = step
            paragraph.headIndent = step
        }

        storage.addAttributes([
            .font: headingFont,
            .foregroundColor: headingColor,
            .paragraphStyle: paragraph,
        ], range: contentRange)

        // The whole heading is a marker pair: `## ` … ` ##`
        var markerRanges: [NSRange] = []
        let absoluteHashes = NSRange(location: contentRange.location + indentSpaces, length: hashes.length)
        markerRanges.append(absoluteHashes)
        if let trailing {
            markerRanges.append(NSRange(location: contentRange.location + trailing.location, length: trailing.length))
        }
        for range in markerRanges where range.length > 0 && NSMaxRange(range) <= NSMaxRange(contentRange) {
            hide(range, in: storage, revealParagraph: revealParagraph)
        }
        protected.append(contentsOf: markerRanges)
    }

    // MARK: - Inline scanning

    private func scanInline(
        _ text: NSString,
        storage: NSTextStorage,
        revealParagraph: NSRange,
        structure: Structure,
        protected: inout [NSRange]
    ) {
        let full = NSRange(location: 0, length: text.length)

        func isInsideProtected(_ range: NSRange) -> Bool {
            for protectedRange in protected where NSIntersectionRange(protectedRange, range).length > 0 {
                return true
            }
            for line in structure.codeLines where NSIntersectionRange(line, range).length > 0 {
                return true
            }
            return false
        }

        func reveal(_ range: NSRange, in storage: NSTextStorage) {
            hide(range, in: storage, revealParagraph: revealParagraph)
        }

        // 1. Inline code — handled before emphasis so that `**` inside code survives.
        enumerate(MarkdownHighlighter.inlineCodeRegex, in: text, range: full) { match, _ in
            guard !isInsideProtected(match.range) else { return }
            let whole = match.range
            let ticks = match.range(at: 1).length
            let content = match.range(at: 2)
            storage.addAttributes([
                .font: self.monoFont,
                .foregroundColor: self.codeColor,
                .backgroundColor: self.codeBackground,
            ], range: content)
            reveal(NSRange(location: whole.location, length: ticks), in: storage)
            reveal(NSRange(location: NSMaxRange(whole) - ticks, length: ticks), in: storage)
            protected.append(whole)
        }

        // 2. Images.
        enumerate(MarkdownHighlighter.imageRegex, in: text, range: full) { match, _ in
            guard !isInsideProtected(match.range) else { return }
            let label = match.range(at: 1)
            let destination = match.range(at: 2)
            let whole = match.range
            storage.addAttributes([
                .foregroundColor: self.secondaryColor,
                .font: self.font(.regular, italic: true),
            ], range: label)
            storage.addAttributes([
                .foregroundColor: self.tertiaryColor,
                .font: self.font(.regular, scale: 0.9),
            ], range: destination)
            self.hideLinkMarkers(around: whole, label: label, storage: storage, revealParagraph: revealParagraph)
            protected.append(whole)
        }

        // 3. Markdown links. The `.link` attribute makes ⌘-click open the destination.
        enumerate(MarkdownHighlighter.linkRegex, in: text, range: full) { match, _ in
            guard !isInsideProtected(match.range) else { return }
            let label = match.range(at: 1)
            let destination = match.range(at: 2)
            let whole = match.range
            storage.addAttributes([
                .foregroundColor: self.linkColor,
                .font: self.font(.regular, scale: 1.02),
            ], range: label)
            storage.addAttributes([
                .foregroundColor: self.tertiaryColor,
                .font: self.font(.regular, scale: 0.88),
            ], range: destination)
            if label.length > 0 {
                let url = text.substring(with: destination)
                storage.addAttribute(.link, value: url, range: label)
            }
            self.hideLinkMarkers(around: whole, label: label, storage: storage, revealParagraph: revealParagraph)
            protected.append(whole)
        }

        // 4. Bare URLs and autolinks.
        enumerate(MarkdownHighlighter.urlRegex, in: text, range: full) { match, _ in
            guard !isInsideProtected(match.range) else { return }
            var range = match.range
            // Trailing punctuation is almost never part of the URL.
            let trailing = ".!,;:?"
            while range.length > 0,
                  let scalar = Unicode.Scalar(text.character(at: NSMaxRange(range) - 1)),
                  trailing.unicodeScalars.contains(scalar) {
                range.length -= 1
            }
            guard range.length > 0 else { return }
            storage.addAttributes([
                .foregroundColor: self.linkColor,
                .font: self.font(.regular, scale: 1.02),
            ], range: range)
            var value = text.substring(with: range)
            if value.hasPrefix("www.") { value = "https://" + value }
            storage.addAttribute(.link, value: value, range: range)
            protected.append(range)
        }

        // 5. Wikilinks.
        enumerate(MarkdownHighlighter.wikiRegex, in: text, range: full) { match, _ in
            guard !isInsideProtected(match.range) else { return }
            storage.addAttributes([
                .foregroundColor: self.linkColor,
                .font: self.font(.medium),
            ], range: match.range(at: 1))
            reveal(NSRange(location: match.range.location, length: 2), in: storage)
            reveal(NSRange(location: NSMaxRange(match.range) - 2, length: 2), in: storage)
            protected.append(match.range)
        }

        // 6. Tags.
        for range in structure.tagRanges where !isInsideProtected(range) {
            storage.addAttributes([
                .foregroundColor: self.tagColor,
                .font: self.font(.medium),
            ], range: range)
        }

        // 7. Emphasis, from the widest marker inwards so nesting survives.
        var emphasised: [NSRange] = []
        func applyEmphasis(
            _ regex: NSRegularExpression,
            _ attributes: [NSAttributedString.Key: Any],
            markerLength: Int,
            protectContent: Bool = true
        ) {
            enumerate(regex, in: text, range: full) { match, _ in
                guard !isInsideProtected(match.range) else { return }
                if emphasised.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { return }
                let whole = match.range
                let content = match.range(at: 1)
                guard content.length > 0 else { return }
                storage.addAttributes(attributes, range: content)
                reveal(NSRange(location: whole.location, length: markerLength), in: storage)
                reveal(NSRange(location: NSMaxRange(whole) - markerLength, length: markerLength), in: storage)
                if protectContent { emphasised.append(whole) }
            }
        }

        applyEmphasis(MarkdownHighlighter.boldItalicRegex, [.font: self.boldItalicFont], markerLength: 3, protectContent: false)
        applyEmphasis(MarkdownHighlighter.boldRegex, [.font: self.boldFont], markerLength: 2)
        applyEmphasis(MarkdownHighlighter.boldUnderRegex, [.font: self.boldFont], markerLength: 2)
        applyEmphasis(MarkdownHighlighter.italicRegex, [.font: self.italicFont], markerLength: 1)
        applyEmphasis(MarkdownHighlighter.italicUnderRegex, [.font: self.italicFont], markerLength: 1)
        applyEmphasis(MarkdownHighlighter.strikeRegex, [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: self.secondaryColor,
        ], markerLength: 2)
        applyEmphasis(MarkdownHighlighter.highlightRegex, [
            .backgroundColor: self.highlightColor,
        ], markerLength: 2)
    }

    private var highlightColor: NSColor {
        NSColor.systemYellow.withAlphaComponent(theme.isDark ? 0.28 : 0.42)
    }

    /// Hides `[`, `](url)` and the closing bracket of a link, leaving only the label.
    private func hideLinkMarkers(
        around whole: NSRange,
        label: NSRange,
        storage: NSTextStorage,
        revealParagraph: NSRange
    ) {
        let ranges = [
            NSRange(location: whole.location, length: max(0, label.location - whole.location)),
            NSRange(location: NSMaxRange(label), length: max(0, NSMaxRange(whole) - NSMaxRange(label))),
        ]
        for range in ranges where range.length > 0 {
            hide(range, in: storage, revealParagraph: revealParagraph)
        }
    }

    private func enumerate(
        _ regex: NSRegularExpression,
        in text: NSString,
        range: NSRange,
        body: (NSTextCheckingResult, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        regex.enumerateMatches(in: text as String, options: [], range: range) { result, _, stop in
            if let result { body(result, stop) }
        }
    }

    // MARK: - Line matchers

    static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.filter { !$0.isWhitespace }
        guard stripped.count >= 3 else { return false }
        guard let first = stripped.first, first == "-" || first == "*" || first == "_" else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    struct ListMatch {
        var markerLength: Int
        var checked: Bool
    }

    static func matchTask(_ line: String) -> ListMatch? {
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        guard index < chars.count, chars[index] == "-" || chars[index] == "*" || chars[index] == "+" else { return nil }
        index += 1
        guard index < chars.count, chars[index] == " " || chars[index] == "\t" else { return nil }
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        guard index + 3 <= chars.count, chars[index] == "[" else { return nil }
        let state = chars[index + 1]
        guard state == " " || state == "x" || state == "X", chars[index + 2] == "]" else { return nil }
        index += 3
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        return ListMatch(markerLength: index, checked: state != " ")
    }

    static func matchBullet(_ line: String) -> ListMatch? {
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        guard index < chars.count, chars[index] == "-" || chars[index] == "*" || chars[index] == "+" else { return nil }
        index += 1
        guard index < chars.count, chars[index] == " " || chars[index] == "\t" else { return nil }
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        return ListMatch(markerLength: index, checked: false)
    }

    static func matchOrdered(_ line: String) -> ListMatch? {
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        var digits = 0
        while index < chars.count, chars[index].isNumber, digits < 9 { index += 1; digits += 1 }
        guard digits > 0, index < chars.count, chars[index] == "." || chars[index] == ")" else { return nil }
        index += 1
        guard index < chars.count, chars[index] == " " || chars[index] == "\t" else { return nil }
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        return ListMatch(markerLength: index, checked: false)
    }

    // MARK: - List behaviour shared with the editor

    struct ListContinuation {
        var marker: String
        var markerLength: Int
        var contentLength: Int
        var isEmptyItem: Bool
    }

    /// Location of the `[ ]` / `[x]` marker inside a task paragraph.
    static func taskBracketRange(in paragraph: NSString) -> NSRange? {
        for candidate in ["[ ]", "[x]", "[X]"] {
            let range = paragraph.range(of: candidate)
            if range.location != NSNotFound { return range }
        }
        return nil
    }

    static func isListParagraph(_ text: String) -> Bool {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if matchTask(line) != nil || matchBullet(line) != nil || matchOrdered(line) != nil {
                return true
            }
        }
        return false
    }

    /// What to insert when the user presses Return at the end of a list item.
    static func listContinuation(for paragraph: String) -> ListContinuation? {
        var line = paragraph
        if line.hasSuffix("\n") { line.removeLast() }
        let ns = line as NSString
        guard ns.length > 0 else { return nil }

        if let task = matchTask(line) {
            let marker = ns.substring(to: min(task.markerLength, ns.length))
                .replacingOccurrences(of: "[x]", with: "[ ]")
                .replacingOccurrences(of: "[X]", with: "[ ]")
            let content = ns.substring(from: min(task.markerLength, ns.length))
                .trimmingCharacters(in: .whitespaces)
            return ListContinuation(
                marker: marker,
                markerLength: task.markerLength,
                contentLength: max(0, ns.length - task.markerLength),
                isEmptyItem: content.isEmpty
            )
        }

        if let bullet = matchBullet(line) {
            let marker = ns.substring(to: min(bullet.markerLength, ns.length))
            let content = ns.substring(from: min(bullet.markerLength, ns.length))
                .trimmingCharacters(in: .whitespaces)
            return ListContinuation(
                marker: marker,
                markerLength: bullet.markerLength,
                contentLength: max(0, ns.length - bullet.markerLength),
                isEmptyItem: content.isEmpty
            )
        }

        if let ordered = matchOrdered(line) {
            let prefix = ns.substring(to: min(ordered.markerLength, ns.length))
            let indent = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
            var rest = Substring(prefix.drop(while: { $0 == " " || $0 == "\t" }))
            var digits = ""
            while let first = rest.first, first.isNumber {
                digits.append(first)
                rest.removeFirst()
            }
            let separator = rest.first.map(String.init) ?? "."
            let next = (Int(digits) ?? 1) + 1
            let marker = indent + String(next) + separator + " "
            let content = ns.substring(from: min(ordered.markerLength, ns.length))
                .trimmingCharacters(in: .whitespaces)
            return ListContinuation(
                marker: marker,
                markerLength: ordered.markerLength,
                contentLength: max(0, ns.length - ordered.markerLength),
                isEmptyItem: content.isEmpty
            )
        }

        return nil
    }

    // MARK: - Tag scanning

    /// Absolute ranges of every inline `#tag` inside `range`. Headings (`# Title`) never
    /// match because a letter must follow the hash immediately.
    static func tagRanges(in text: NSString, range: NSRange) -> [NSRange] {
        let hashChar: unichar = 0x23
        let openParen: unichar = 0x28
        let openBracket: unichar = 0x5B
        let underscore: unichar = 0x5F
        let hyphen: unichar = 0x2D
        let slash: unichar = 0x2F
        let space: unichar = 0x20
        let tab: unichar = 0x09

        func isTagBody(_ c: unichar) -> Bool {
            if c == underscore || c == hyphen || c == slash { return true }
            guard let scalar = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        }
        func isSeparator(_ c: unichar) -> Bool {
            c == slash || c == hyphen || c == underscore
        }

        var result: [NSRange] = []
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            guard text.character(at: index) == hashChar else {
                index += 1
                continue
            }
            let previous: unichar = index > range.location ? text.character(at: index - 1) : space
            let atBoundary = index == range.location
                || previous == space
                || previous == tab
                || previous == openParen
                || previous == openBracket
            guard atBoundary, index + 1 < end else {
                index += 1
                continue
            }
            guard let firstScalar = Unicode.Scalar(text.character(at: index + 1)),
                  CharacterSet.letters.contains(firstScalar) else {
                index += 1
                continue
            }
            var cursor = index + 1
            while cursor < end, isTagBody(text.character(at: cursor)) { cursor += 1 }
            var tagEnd = cursor
            while tagEnd > index + 1, isSeparator(text.character(at: tagEnd - 1)) { tagEnd -= 1 }
            if tagEnd > index + 1 {
                result.append(NSRange(location: index, length: tagEnd - index))
            }
            index = max(cursor, index + 1)
        }
        return result
    }

    // MARK: - Regexes

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Every pattern below is a compile-time constant, so a failure would be a programmer error.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    static let inlineCodeRegex = regex("(`{1,})(.+?)\\1")
    static let imageRegex = regex("!\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+\"[^\"]*\")?\\)")
    static let linkRegex = regex("(?<!!)\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+\"[^\"]*\")?\\)")
    static let urlRegex = regex("(?:https?://|www\\.)[^\\s<>\"'`\\]\\)]+")
    static let wikiRegex = regex("\\[\\[([^\\]\\n]+)\\]\\]")
    static let boldItalicRegex = regex("\\*\\*\\*(?=\\S)([^*]+?)(?<=\\S)\\*\\*\\*")
    static let boldRegex = regex("(?<!\\*)\\*\\*(?=\\S)([^*]+?)(?<=\\S)\\*\\*(?!\\*)")
    static let boldUnderRegex = regex("(?<![\\w_])__(?=\\S)([^_]+?)(?<=\\S)__(?![\\w_])")
    static let italicRegex = regex("(?<![*\\w])\\*(?!\\*)(?=\\S)([^*\\n]+?)(?<=\\S)\\*(?!\\*)")
    static let italicUnderRegex = regex("(?<![\\w_])_(?!_)(?=\\S)([^_\\n]+?)(?<=\\S)_(?![\\w_])")
    static let strikeRegex = regex("~~(?=\\S)([^~]+?)(?<=\\S)~~")
    static let highlightRegex = regex("==(?=\\S)([^=]+?)(?<=\\S)==")
}
