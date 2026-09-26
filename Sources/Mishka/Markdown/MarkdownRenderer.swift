import Foundation

// MARK: - Public API

/// A dependency-free Markdown → HTML renderer.
///
/// The renderer is a hand written, single pass block parser plus a recursive inline
/// scanner. It never uses the filesystem or the network: the caller supplies the note
/// folder as `basePath` and relative image paths are rewritten to `file://` URLs so a
/// `WKWebView` can load them.
///
/// All user supplied text is HTML escaped before it is written to the output, and every
/// link / image destination is sanitised so that `javascript:` and friends can never end
/// up inside an attribute.
enum MarkdownRenderer {

    /// Complete standalone HTML document, ready for `WKWebView.loadHTMLString`.
    /// `basePath` is the folder of the note file; relative image paths are rewritten
    /// to `file://` URLs against it. Pass nil when unknown.
    static func html(from markdown: String, theme: Theme, fontCSS: String, basePath: URL?) -> String {
        let body = bodyHTML(from: markdown, theme: theme, basePath: basePath)
        let scheme = theme.isDark ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\(scheme)">
        <style>
        \(css(for: theme, fontCSS: fontCSS))
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Body fragment only (no `<html>` / `<head>`), used for "Copy as HTML" and export.
    static func bodyHTML(from markdown: String, theme: Theme, basePath: URL?) -> String {
        let document = MDRDocument.parse(markdown)
        var parser = MDRBlockParser(
            lines: document.lines,
            refs: document.refs,
            basePath: basePath,
            depth: 0
        )
        let content = parser.render()
        if content.isEmpty {
            return "<div class=\"markdown-body\"></div>"
        }
        return "<div class=\"markdown-body\">\n\(content)\n</div>"
    }

    /// The stylesheet alone. `fontCSS` is an already-built CSS font fragment
    /// (e.g. `font-family: -apple-system, sans-serif; font-size: 16px;`).
    static func css(for theme: Theme, fontCSS: String) -> String {
        MDRStylesheet.build(theme: theme, fontCSS: fontCSS)
    }
}

// MARK: - Small model types

private struct MDRRefDef {
    let url: String
    let title: String?
}

private struct MDRFence {
    let marker: Character
    let count: Int
    let info: String
}

private struct MDRListLine {
    let indent: Int
    let ordered: Bool
    let number: Int
    let contentColumn: Int
    var content: String
    let isTask: Bool
    let isChecked: Bool
}

private struct MDRListItem {
    let content: String
    let isTask: Bool
    let isChecked: Bool
    var children: [MDRListNode] = []
}

private struct MDRListNode {
    let ordered: Bool
    let start: Int
    var items: [MDRListItem]
}

private enum MDRTableAlign {
    case none
    case left
    case center
    case right

    var styleAttribute: String {
        switch self {
        case .none: return ""
        case .left: return " style=\"text-align:left\""
        case .center: return " style=\"text-align:center\""
        case .right: return " style=\"text-align:right\""
        }
    }
}

private struct MDRDocument {
    let lines: [String]
    let refs: [String: MDRRefDef]

    static func parse(_ markdown: String) -> MDRDocument {
        var normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }

        var lines = normalized.components(separatedBy: "\n")
        for index in lines.indices {
            lines[index] = MDRUtil.expandLeadingTabs(lines[index])
        }

        // Harvest `[id]: url "title"` definitions, skipping fenced code.
        var refs: [String: MDRRefDef] = [:]
        var openFence: MDRFence?
        for index in lines.indices {
            let chars = Array(lines[index])
            if let fence = openFence {
                if MDRUtil.fenceClose(chars, fence) { openFence = nil }
                continue
            }
            if let fence = MDRUtil.fenceStart(chars) {
                openFence = fence
                continue
            }
            if let (label, definition) = MDRUtil.parseReferenceDefinition(lines[index]) {
                refs[label] = definition
                lines[index] = ""
            }
        }

        return MDRDocument(lines: lines, refs: refs)
    }
}

// MARK: - Block parser

private struct MDRBlockParser {
    let lines: [String]
    let refs: [String: MDRRefDef]
    let basePath: URL?
    let depth: Int

    /// Guards nested blockquote / list recursion.
    static let maxDepth = 12

    mutating func render() -> String {
        var blocks: [String] = []
        let count = lines.count
        var index = 0

        // YAML front matter at the very top of the note becomes a metadata card instead
        // of a stray horizontal rule followed by a wall of `key: value` text.
        if depth == 0, let frontMatter = MDRUtil.frontMatter(lines: lines) {
            blocks.append(MDRUtil.renderFrontMatter(frontMatter))
            index = frontMatter.endIndex
        }

        while index < count {
            let line = lines[index]
            if MDRUtil.isBlank(line) {
                index += 1
                continue
            }

            if depth >= MDRBlockParser.maxDepth {
                let rest = lines[index...].joined(separator: "\n")
                blocks.append("<p>" + MDRUtil.escape(rest) + "</p>")
                break
            }

            let chars = Array(line)

            // Fenced code block ------------------------------------------------
            if let fence = MDRUtil.fenceStart(chars) {
                var body: [String] = []
                var scan = index + 1
                while scan < count {
                    if MDRUtil.fenceClose(Array(lines[scan]), fence) {
                        scan += 1
                        break
                    }
                    body.append(lines[scan])
                    scan += 1
                }
                index = scan
                let language = MDRUtil.languageClass(fence.info)
                let classAttribute = language.isEmpty ? "" : " class=\"language-\(language)\""
                let code = MDRUtil.escape(body.joined(separator: "\n"))
                blocks.append("<pre><code\(classAttribute)>\(code)</code></pre>")
                continue
            }

            // ATX heading ------------------------------------------------------
            if let (level, text) = MDRUtil.atxHeading(chars) {
                let inner = MDRUtil.renderInline(text, refs: refs, basePath: basePath, depth: depth)
                blocks.append("<h\(level)>\(inner)</h\(level)>")
                index += 1
                continue
            }

            // Thematic break ---------------------------------------------------
            if MDRUtil.isThematicBreak(chars) {
                blocks.append("<hr>")
                index += 1
                continue
            }

            // Blockquote -------------------------------------------------------
            if MDRUtil.blockquoteContent(chars) != nil {
                var inner: [String] = []
                var scan = index
                while scan < count {
                    let candidate = lines[scan]
                    if MDRUtil.isBlank(candidate) {
                        var lookahead = scan + 1
                        while lookahead < count && MDRUtil.isBlank(lines[lookahead]) {
                            lookahead += 1
                        }
                        if lookahead < count, MDRUtil.blockquoteContent(Array(lines[lookahead])) != nil {
                            inner.append("")
                            scan = lookahead
                            continue
                        }
                        break
                    }
                    if let stripped = MDRUtil.blockquoteContent(Array(candidate)) {
                        inner.append(stripped)
                        scan += 1
                        continue
                    }
                    if MDRUtil.isLazyContinuation(Array(candidate)) {
                        inner.append(candidate)
                        scan += 1
                        continue
                    }
                    break
                }
                index = scan
                var child = MDRBlockParser(lines: inner, refs: refs, basePath: basePath, depth: depth + 1)
                let innerHTML = child.render()
                if innerHTML.isEmpty {
                    blocks.append("<blockquote></blockquote>")
                } else {
                    blocks.append("<blockquote>\n\(innerHTML)\n</blockquote>")
                }
                continue
            }

            // GFM table --------------------------------------------------------
            if index + 1 < count,
               MDRUtil.containsPipe(chars),
               let alignments = MDRUtil.tableAlignments(Array(lines[index + 1])) {
                let header = MDRUtil.splitTableRow(line)
                var rows: [[String]] = []
                var scan = index + 2
                while scan < count {
                    let candidate = lines[scan]
                    if MDRUtil.isBlank(candidate) || !MDRUtil.containsPipe(Array(candidate)) {
                        break
                    }
                    rows.append(MDRUtil.splitTableRow(candidate))
                    scan += 1
                }
                index = scan
                blocks.append(MDRUtil.renderTable(
                    header: header,
                    alignments: alignments,
                    rows: rows,
                    refs: refs,
                    basePath: basePath,
                    depth: depth
                ))
                continue
            }

            // List -------------------------------------------------------------
            if let first = MDRUtil.parseListLine(line) {
                let listIndent = first.indent
                var items: [MDRListLine] = [first]
                var scan = index + 1
                while scan < count {
                    let candidate = lines[scan]
                    if MDRUtil.isBlank(candidate) {
                        var lookahead = scan + 1
                        while lookahead < count && MDRUtil.isBlank(lines[lookahead]) {
                            lookahead += 1
                        }
                        if lookahead < count,
                           let next = MDRUtil.parseListLine(lines[lookahead]),
                           next.indent >= listIndent {
                            scan = lookahead
                            continue
                        }
                        break
                    }
                    if let next = MDRUtil.parseListLine(candidate) {
                        if next.indent < listIndent { break }
                        items.append(next)
                        scan += 1
                        continue
                    }
                    let indent = MDRUtil.indentWidth(Array(candidate))
                    if indent >= listIndent + 2, !items.isEmpty {
                        let column = max(items[items.count - 1].contentColumn, listIndent + 2)
                        let stripped = MDRUtil.stripIndent(candidate, column)
                        if items[items.count - 1].content.isEmpty {
                            items[items.count - 1].content = stripped
                        } else {
                            items[items.count - 1].content += "\n" + stripped
                        }
                        scan += 1
                        continue
                    }
                    break
                }
                index = scan
                blocks.append(MDRUtil.renderList(items, refs: refs, basePath: basePath, depth: depth))
                continue
            }

            // Indented code block ----------------------------------------------
            if MDRUtil.indentWidth(chars) >= 4 {
                var code: [String] = []
                var pendingBlanks: [String] = []
                var scan = index
                while scan < count {
                    let candidate = lines[scan]
                    if MDRUtil.isBlank(candidate) {
                        pendingBlanks.append("")
                        scan += 1
                        continue
                    }
                    if MDRUtil.indentWidth(Array(candidate)) >= 4 {
                        code.append(contentsOf: pendingBlanks)
                        pendingBlanks.removeAll()
                        code.append(MDRUtil.stripIndent(candidate, 4))
                        scan += 1
                        continue
                    }
                    break
                }
                index = scan
                blocks.append("<pre><code>" + MDRUtil.escape(code.joined(separator: "\n")) + "</code></pre>")
                continue
            }

            // Paragraph --------------------------------------------------------
            var paragraph: [String] = [line]
            var scan = index + 1
            while scan < count {
                let candidate = lines[scan]
                if MDRUtil.isBlank(candidate) { break }
                if MDRUtil.startsBlock(lines, at: scan) { break }
                paragraph.append(candidate)
                scan += 1
            }
            index = scan
            let text = paragraph.joined(separator: "\n")
            blocks.append("<p>" + MDRUtil.renderInline(text, refs: refs, basePath: basePath, depth: depth) + "</p>")
        }

        return blocks.joined(separator: "\n")
    }
}

// MARK: - Utilities: scanning, escaping, inline rendering

private enum MDRUtil {

    static let maxInlineDepth = 16
    static let escapable: Set<Character> = [
        "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", ".", "!",
        ">", "~", "|", "=", "<", "$", "%", "&", "\"", "'", ":", ";", ",", "?", "@", "^"
    ]
    static let urlLiterals: [[Character]] = ["https://", "http://", "mailto:", "ftp://", "www."].map { Array($0) }
    static let wwwLiteral: [Character] = Array("www.")

    // MARK: Escaping

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count + 8)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: Character helpers

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func containsPipe(_ chars: [Character]) -> Bool {
        chars.contains("|")
    }

    /// A leading `---` block whose body looks like `key: value` metadata.
    struct MDRFrontMatter {
        var pairs: [(String, String)]
        var endIndex: Int
    }

    static func frontMatter(lines: [String]) -> MDRFrontMatter? {
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var pairs: [(String, String)] = []
        var index = 1
        var closed = false
        while index < lines.count {
            let marker = lines[index].trimmingCharacters(in: .whitespaces)
            if marker == "---" || marker == "..." {
                closed = true
                index += 1
                break
            }
            let raw = lines[index]
            if let colon = raw.firstIndex(of: ":") {
                let key = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !key.hasPrefix("#") {
                    pairs.append((key, value))
                }
            } else if !marker.isEmpty {
                // Not metadata after all — leave the block alone.
                return nil
            }
            index += 1
        }
        guard closed, !pairs.isEmpty else { return nil }
        return MDRFrontMatter(pairs: pairs, endIndex: index)
    }

    static func renderFrontMatter(_ matter: MDRFrontMatter) -> String {
        var out = "<div class=\"front-matter\">"
        for (key, value) in matter.pairs {
            out += "<span class=\"fm-key\">" + escape(key) + "</span>"
            out += "<span class=\"fm-value\">" + escape(value) + "</span>"
        }
        out += "</div>"
        return out
    }

    static func indentWidth(_ chars: [Character]) -> Int {
        var width = 0
        var index = 0
        while index < chars.count {
            if chars[index] == " " {
                width += 1
            } else if chars[index] == "\t" {
                width += 4
            } else {
                break
            }
            index += 1
        }
        return width
    }

    static func expandLeadingTabs(_ line: String) -> String {
        let chars = Array(line)
        var out = ""
        var column = 0
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == " " {
                out.append(" ")
                column += 1
                index += 1
            } else if character == "\t" {
                let pad = 4 - (column % 4)
                out += String(repeating: " ", count: pad)
                column += pad
                index += 1
            } else {
                out += String(chars[index...])
                return out
            }
        }
        return out
    }

    static func stripIndent(_ line: String, _ width: Int) -> String {
        let chars = Array(line)
        var column = 0
        var index = 0
        while index < chars.count && column < width {
            if chars[index] == " " {
                column += 1
                index += 1
            } else if chars[index] == "\t" {
                column += 4
                index += 1
            } else {
                break
            }
        }
        var rest = String(chars[index...])
        if column > width {
            rest = String(repeating: " ", count: column - width) + rest
        }
        return rest
    }

    static func matches(_ chars: [Character], at index: Int, _ literal: [Character]) -> Bool {
        if index + literal.count > chars.count { return false }
        var offset = 0
        while offset < literal.count {
            if chars[index + offset] != literal[offset] { return false }
            offset += 1
        }
        return true
    }

    static func matchesCaseInsensitive(_ chars: [Character], at index: Int, _ literal: [Character]) -> Bool {
        if index + literal.count > chars.count { return false }
        var offset = 0
        while offset < literal.count {
            if Character(chars[index + offset].lowercased()) != literal[offset] { return false }
            offset += 1
        }
        return true
    }

    // MARK: Block detection

    static func fenceStart(_ chars: [Character]) -> MDRFence? {
        var index = 0
        var spaces = 0
        while index < chars.count && chars[index] == " " && spaces < 4 {
            spaces += 1
            index += 1
        }
        guard spaces <= 3, index < chars.count else { return nil }
        let marker = chars[index]
        guard marker == "`" || marker == "~" else { return nil }
        var run = 0
        while index < chars.count && chars[index] == marker {
            run += 1
            index += 1
        }
        guard run >= 3 else { return nil }
        let info = String(chars[index...]).trimmingCharacters(in: .whitespaces)
        if marker == "`" && info.contains("`") { return nil }
        return MDRFence(marker: marker, count: run, info: info)
    }

    static func fenceClose(_ chars: [Character], _ fence: MDRFence) -> Bool {
        var index = 0
        var spaces = 0
        while index < chars.count && chars[index] == " " && spaces < 4 {
            spaces += 1
            index += 1
        }
        guard spaces <= 3, index < chars.count, chars[index] == fence.marker else { return false }
        var run = 0
        while index < chars.count && chars[index] == fence.marker {
            run += 1
            index += 1
        }
        guard run >= fence.count else { return false }
        while index < chars.count {
            if chars[index] != " " && chars[index] != "\t" { return false }
            index += 1
        }
        return true
    }

    static func languageClass(_ info: String) -> String {
        var out = ""
        for character in info {
            if character == " " || character == "\t" { break }
            if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "+" || character == "#" || character == "." {
                out.append(character)
            }
        }
        return out
    }

    static func atxHeading(_ chars: [Character]) -> (Int, String)? {
        var index = 0
        var spaces = 0
        while index < chars.count && chars[index] == " " && spaces < 4 {
            spaces += 1
            index += 1
        }
        guard spaces <= 3, index < chars.count, chars[index] == "#" else { return nil }
        var level = 0
        while index < chars.count && chars[index] == "#" && level < 7 {
            level += 1
            index += 1
        }
        guard level >= 1, level <= 6 else { return nil }
        if index < chars.count {
            guard chars[index] == " " || chars[index] == "\t" else { return nil }
            while index < chars.count && (chars[index] == " " || chars[index] == "\t") {
                index += 1
            }
        }
        let text = stripClosingHashes(String(chars[index...]))
        return (level, text)
    }

    static func stripClosingHashes(_ text: String) -> String {
        var chars = Array(text)
        while let last = chars.last, last == " " || last == "\t" {
            chars.removeLast()
        }
        var end = chars.count
        while end > 0 && chars[end - 1] == "#" {
            end -= 1
        }
        if end < chars.count {
            if end == 0 { return "" }
            if chars[end - 1] == " " || chars[end - 1] == "\t" {
                chars.removeSubrange(end..<chars.count)
                while let last = chars.last, last == " " || last == "\t" {
                    chars.removeLast()
                }
            }
        }
        return String(chars)
    }

    static func isThematicBreak(_ chars: [Character]) -> Bool {
        var index = 0
        var spaces = 0
        while index < chars.count && chars[index] == " " && spaces < 4 {
            spaces += 1
            index += 1
        }
        guard spaces <= 3, index < chars.count else { return false }
        let marker = chars[index]
        guard marker == "-" || marker == "*" || marker == "_" else { return false }
        var run = 0
        while index < chars.count {
            let character = chars[index]
            if character == marker {
                run += 1
            } else if character != " " && character != "\t" {
                return false
            }
            index += 1
        }
        return run >= 3
    }

    static func blockquoteContent(_ chars: [Character]) -> String? {
        var index = 0
        var spaces = 0
        while index < chars.count && chars[index] == " " && spaces < 4 {
            spaces += 1
            index += 1
        }
        guard spaces <= 3, index < chars.count, chars[index] == ">" else { return nil }
        index += 1
        if index < chars.count && chars[index] == " " {
            index += 1
        }
        return String(chars[index...])
    }

    static func isLazyContinuation(_ chars: [Character]) -> Bool {
        if fenceStart(chars) != nil { return false }
        if atxHeading(chars) != nil { return false }
        if isThematicBreak(chars) { return false }
        if blockquoteContent(chars) != nil { return false }
        if parseListLine(String(chars)) != nil { return false }
        return true
    }

    static func startsBlock(_ lines: [String], at index: Int) -> Bool {
        let chars = Array(lines[index])
        if fenceStart(chars) != nil { return true }
        if atxHeading(chars) != nil { return true }
        if isThematicBreak(chars) { return true }
        if blockquoteContent(chars) != nil { return true }
        if parseListLine(lines[index]) != nil { return true }
        if index + 1 < lines.count, containsPipe(chars), tableAlignments(Array(lines[index + 1])) != nil {
            return true
        }
        return false
    }

    // MARK: Lists

    static func parseListLine(_ line: String) -> MDRListLine? {
        let chars = Array(line)
        var index = 0
        var indent = 0
        while index < chars.count {
            if chars[index] == " " {
                indent += 1
                index += 1
            } else if chars[index] == "\t" {
                indent += 4
                index += 1
            } else {
                break
            }
        }
        guard index < chars.count else { return nil }
        let marker = chars[index]
        var ordered = false
        var number = 1
        var markerEnd = index
        if marker == "-" || marker == "*" || marker == "+" {
            markerEnd = index + 1
        } else if marker.isNumber {
            var scan = index
            var digits = ""
            while scan < chars.count && chars[scan].isNumber && digits.count < 9 {
                digits.append(chars[scan])
                scan += 1
            }
            guard scan < chars.count, chars[scan] == "." || chars[scan] == ")" else { return nil }
            ordered = true
            number = Int(digits) ?? 1
            markerEnd = scan + 1
        } else {
            return nil
        }

        var contentStart = markerEnd
        if contentStart < chars.count && (chars[contentStart] == " " || chars[contentStart] == "\t") {
            var spaces = 0
            while contentStart < chars.count,
                  (chars[contentStart] == " " || chars[contentStart] == "\t"),
                  spaces < 4 {
                contentStart += 1
                spaces += 1
            }
        } else if contentStart != chars.count {
            return nil
        }

        var content = String(chars[contentStart...])
        var isTask = false
        var isChecked = false
        let contentChars = Array(content)
        if contentChars.count >= 3,
           contentChars[0] == "[",
           contentChars[1] == " " || contentChars[1] == "x" || contentChars[1] == "X",
           contentChars[2] == "]" {
            if contentChars.count == 3 || contentChars[3] == " " || contentChars[3] == "\t" {
                isTask = true
                isChecked = contentChars[1] == "x" || contentChars[1] == "X"
                var bodyStart = 3
                while bodyStart < contentChars.count,
                      contentChars[bodyStart] == " " || contentChars[bodyStart] == "\t" {
                    bodyStart += 1
                }
                content = String(contentChars[bodyStart...])
            }
        }

        let column = indent + (contentStart - index)
        return MDRListLine(
            indent: indent,
            ordered: ordered,
            number: number,
            contentColumn: column,
            content: content,
            isTask: isTask,
            isChecked: isChecked
        )
    }

    static func renderList(_ lines: [MDRListLine], refs: [String: MDRRefDef], basePath: URL?, depth: Int) -> String {
        var index = 0
        var blocks: [String] = []
        while index < lines.count {
            guard let node = buildListNode(lines, &index, lines[index].indent) else { break }
            blocks.append(renderListNode(node, refs: refs, basePath: basePath, depth: depth))
        }
        return blocks.joined(separator: "\n")
    }

    static func buildListNode(_ lines: [MDRListLine], _ index: inout Int, _ minIndent: Int) -> MDRListNode? {
        guard index < lines.count, lines[index].indent >= minIndent else { return nil }
        let listIndent = lines[index].indent
        let ordered = lines[index].ordered
        let start = lines[index].number
        var items: [MDRListItem] = []

        while index < lines.count {
            let line = lines[index]
            if line.indent < listIndent { break }
            if line.indent == listIndent {
                if line.ordered != ordered { break }
                items.append(MDRListItem(content: line.content, isTask: line.isTask, isChecked: line.isChecked))
                index += 1
            } else {
                guard var parent = items.last else { break }
                guard let child = buildListNode(lines, &index, line.indent) else { break }
                parent.children.append(child)
                items[items.count - 1] = parent
            }
        }

        return MDRListNode(ordered: ordered, start: start, items: items)
    }

    static func renderListNode(_ node: MDRListNode, refs: [String: MDRRefDef], basePath: URL?, depth: Int) -> String {
        let tag = node.ordered ? "ol" : "ul"
        let open = (node.ordered && node.start != 1) ? "<\(tag) start=\"\(node.start)\">" : "<\(tag)>"
        var rows: [String] = [open]
        for item in node.items {
            var buffer = "<li>"
            if item.isTask {
                buffer += "<input type=\"checkbox\" disabled"
                if item.isChecked { buffer += " checked" }
                buffer += "> "
            }
            buffer += renderItemContent(item.content, refs: refs, basePath: basePath, depth: depth)
            for child in item.children {
                buffer += "\n" + renderListNode(child, refs: refs, basePath: basePath, depth: depth)
            }
            buffer += "</li>"
            rows.append(buffer)
        }
        rows.append("</\(tag)>")
        return rows.joined(separator: "\n")
    }

    static func renderItemContent(_ content: String, refs: [String: MDRRefDef], basePath: URL?, depth: Int) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        var parser = MDRBlockParser(
            lines: trimmed.components(separatedBy: "\n"),
            refs: refs,
            basePath: basePath,
            depth: depth + 1
        )
        let html = parser.render()
        if html.hasPrefix("<p>"), html.hasSuffix("</p>") {
            let inner = String(html.dropFirst(3).dropLast(4))
            if !inner.contains("<p>") { return inner }
        }
        return html
    }

    // MARK: Tables

    static func splitTableRow(_ line: String) -> [String] {
        let chars = Array(line)
        var cells: [String] = []
        var current = ""
        var index = 0
        while index < chars.count && (chars[index] == " " || chars[index] == "\t") {
            index += 1
        }
        if index < chars.count && chars[index] == "|" {
            index += 1
        }
        while index < chars.count {
            let character = chars[index]
            if character == "\\" && index + 1 < chars.count && chars[index + 1] == "|" {
                current.append("|")
                index += 2
                continue
            }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                index += 1
                continue
            }
            current.append(character)
            index += 1
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty || cells.isEmpty {
            cells.append(tail)
        }
        return cells
    }

    static func tableAlignments(_ chars: [Character]) -> [MDRTableAlign]? {
        let line = String(chars)
        guard line.contains("|") else { return nil }
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MDRTableAlign] = []
        for cell in cells {
            let trimmed = Array(cell.trimmingCharacters(in: .whitespaces))
            guard !trimmed.isEmpty else { return nil }
            var start = 0
            var end = trimmed.count
            var left = false
            var right = false
            if trimmed[start] == ":" {
                left = true
                start += 1
            }
            if end - 1 > start && trimmed[end - 1] == ":" {
                right = true
                end -= 1
            }
            guard end - start >= 1 else { return nil }
            var offset = start
            while offset < end {
                if trimmed[offset] != "-" { return nil }
                offset += 1
            }
            if left && right {
                alignments.append(.center)
            } else if right {
                alignments.append(.right)
            } else if left {
                alignments.append(.left)
            } else {
                alignments.append(.none)
            }
        }
        return alignments
    }

    static func renderTable(
        header: [String],
        alignments: [MDRTableAlign],
        rows: [[String]],
        refs: [String: MDRRefDef],
        basePath: URL?,
        depth: Int
    ) -> String {
        let columns = alignments.count
        // Two wrappers on purpose: WebKit does not clip a border-radius on a scroll
        // container, so the outer box scrolls and the inner one draws the rounded card.
        var out = "<div class=\"table-scroll\">\n<div class=\"table-wrap\">\n<table>\n<thead>\n<tr>"
        for column in 0..<columns {
            let text = column < header.count ? header[column] : ""
            let inner = renderInline(text, refs: refs, basePath: basePath, depth: depth)
            out += "<th\(alignments[column].styleAttribute)>\(inner)</th>"
        }
        out += "</tr>\n</thead>\n<tbody>"
        for row in rows {
            out += "\n<tr>"
            for column in 0..<columns {
                let text = column < row.count ? row[column] : ""
                let inner = renderInline(text, refs: refs, basePath: basePath, depth: depth)
                out += "<td\(alignments[column].styleAttribute)>\(inner)</td>"
            }
            out += "</tr>"
        }
        out += "\n</tbody>\n</table>\n</div>\n</div>"
        return out
    }

    // MARK: Reference definitions

    static func normalizeLabel(_ label: String) -> String {
        let pieces = label.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        return pieces.joined(separator: " ")
    }

    static func parseReferenceDefinition(_ line: String) -> (String, MDRRefDef)? {
        let chars = Array(line)
        var index = 0
        var spaces = 0
        while index < chars.count && chars[index] == " " && spaces < 3 {
            spaces += 1
            index += 1
        }
        guard spaces <= 3, index < chars.count, chars[index] == "[" else { return nil }
        let labelStart = index
        index += 1
        var depth = 0
        var labelEnd = -1
        while index < chars.count {
            let character = chars[index]
            if character == "\\" {
                index += 2
                continue
            }
            if character == "[" {
                depth += 1
            } else if character == "]" {
                if depth == 0 {
                    labelEnd = index
                    break
                }
                depth -= 1
            }
            index += 1
        }
        guard labelEnd > labelStart else { return nil }
        let rawLabel = String(chars[(labelStart + 1)..<labelEnd])
        guard !rawLabel.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        index = labelEnd + 1
        guard index < chars.count, chars[index] == ":" else { return nil }
        index += 1
        while index < chars.count && (chars[index] == " " || chars[index] == "\t") {
            index += 1
        }
        guard index < chars.count else { return nil }

        var destination = ""
        if chars[index] == "<" {
            index += 1
            while index < chars.count && chars[index] != ">" {
                if chars[index] == "\\" && index + 1 < chars.count {
                    destination.append(chars[index + 1])
                    index += 2
                    continue
                }
                destination.append(chars[index])
                index += 1
            }
            guard index < chars.count else { return nil }
            index += 1
        } else {
            while index < chars.count {
                let character = chars[index]
                if character == "\\" && index + 1 < chars.count {
                    destination.append(chars[index + 1])
                    index += 2
                    continue
                }
                if character == " " || character == "\t" { break }
                destination.append(character)
                index += 1
            }
        }
        guard !destination.isEmpty else { return nil }

        var title: String?
        let titleStart = index
        while index < chars.count && (chars[index] == " " || chars[index] == "\t") {
            index += 1
        }
        if index < chars.count && (chars[index] == "\"" || chars[index] == "'" || chars[index] == "(") {
            let opener = chars[index]
            let closer: Character = opener == "(" ? ")" : opener
            index += 1
            var collected = ""
            var closed = false
            while index < chars.count {
                if chars[index] == "\\" && index + 1 < chars.count {
                    collected.append(chars[index + 1])
                    index += 2
                    continue
                }
                if chars[index] == closer {
                    closed = true
                    index += 1
                    break
                }
                collected.append(chars[index])
                index += 1
            }
            if closed {
                title = collected
            } else {
                index = titleStart
                title = nil
            }
        }
        while index < chars.count && (chars[index] == " " || chars[index] == "\t") {
            index += 1
        }
        guard index >= chars.count else { return nil }
        return (normalizeLabel(rawLabel), MDRRefDef(url: destination, title: title))
    }

    // MARK: URL sanitising

    static func sanitizedURL(_ raw: String, isImage: Bool, basePath: URL?) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        var probe = ""
        for scalar in decoded.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { continue }
            probe.unicodeScalars.append(scalar)
        }

        if let colon = probe.firstIndex(of: ":") {
            let prefix = String(probe[probe.startIndex..<colon]).lowercased()
            let looksLikeScheme = !prefix.isEmpty
                && (prefix.first?.isLetter ?? false)
                && prefix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
            if looksLikeScheme {
                switch prefix {
                case "http", "https", "mailto", "file":
                    return trimmed
                default:
                    return nil
                }
            }
        }

        if isImage, let base = basePath, !trimmed.hasPrefix("#") {
            return fileURL(for: trimmed, basePath: base)
        }
        return trimmed
    }

    static func fileURL(for path: String, basePath: URL) -> String {
        if path.hasPrefix("file:") { return path }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).absoluteString
        }
        if path.hasPrefix("~") {
            let expanded = (path as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).absoluteString
        }
        return URL(fileURLWithPath: path, relativeTo: basePath).absoluteString
    }

    static func trimTrailingURLPunctuation(_ text: String) -> String {
        var out = text
        let trailing: Set<Character> = [".", ",", ";", ":", "!", "?", "\"", "'", "*", "_", "~"]
        while let last = out.last, trailing.contains(last) {
            out.removeLast()
        }
        while let last = out.last, last == ")" || last == "]" || last == "}" {
            let opener: Character
            switch last {
            case ")": opener = "("
            case "]": opener = "["
            default: opener = "{"
            }
            let opens = out.filter { $0 == opener }.count
            let closes = out.filter { $0 == last }.count
            if closes > opens {
                out.removeLast()
            } else {
                break
            }
        }
        return out
    }

    static func isURLStart(_ chars: [Character], at index: Int) -> Bool {
        switch chars[index] {
        case "h", "H", "m", "M", "w", "W", "f", "F": break
        default: return false
        }
        if index > 0, isWordCharacter(chars[index - 1]) { return false }
        return true
    }

    // MARK: Inline rendering

    static func renderInline(_ text: String, refs: [String: MDRRefDef], basePath: URL?, depth: Int) -> String {
        if text.isEmpty { return "" }
        if depth > maxInlineDepth { return escape(text) }
        var scanner = MDRInlineScanner(
            chars: Array(text),
            refs: refs,
            basePath: basePath,
            depth: depth
        )
        scanner.run()
        return scanner.out
    }
}

// MARK: - Inline scanner

private struct MDRInlineScanner {
    let chars: [Character]
    let refs: [String: MDRRefDef]
    let basePath: URL?
    let depth: Int
    let end: Int
    var index = 0
    var out = ""

    init(chars: [Character], refs: [String: MDRRefDef], basePath: URL?, depth: Int) {
        self.chars = chars
        self.refs = refs
        self.basePath = basePath
        self.depth = depth
        self.end = chars.count
        self.out = ""
        self.out.reserveCapacity(chars.count + 8)
    }

    mutating func run() {
        while index < end {
            let character = chars[index]
            switch character {
            case "\\":
                if index + 1 < end && MDRUtil.escapable.contains(chars[index + 1]) {
                    appendEscaped(chars[index + 1])
                    index += 2
                } else {
                    out += "\\"
                    index += 1
                }
            case "`":
                parseCode()
            case "!":
                if index + 1 < end && chars[index + 1] == "[", parseImage() {
                    // consumed
                } else {
                    appendEscaped(character)
                    index += 1
                }
            case "[":
                if index + 1 < end && chars[index + 1] == "[" {
                    if !parseWikilink() {
                        appendEscaped(character)
                        index += 1
                    }
                } else if !parseLink() {
                    appendEscaped(character)
                    index += 1
                }
            case "<":
                if !parseAutolink() {
                    out += "&lt;"
                    index += 1
                }
            case "=":
                if !parseHighlight() {
                    appendEscaped(character)
                    index += 1
                }
            case "~":
                if !parseStrikethrough() {
                    appendEscaped(character)
                    index += 1
                }
            case "*", "_":
                if !parseEmphasis() {
                    appendEscaped(character)
                    index += 1
                }
            case "#":
                if !parseTag() {
                    out += "#"
                    index += 1
                }
            case "\n":
                handleNewline()
            default:
                if MDRUtil.isURLStart(chars, at: index), parseBareURL() {
                    // consumed
                } else {
                    appendEscaped(character)
                    index += 1
                }
            }
        }
    }

    // MARK: Primitives

    mutating func appendEscaped(_ character: Character) {
        switch character {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&#39;"
        default: out.append(character)
        }
    }

    mutating func handleNewline() {
        var spaces = 0
        var look = index - 1
        while look >= 0 && chars[look] == " " {
            spaces += 1
            look -= 1
        }
        if spaces >= 2 {
            let removable = min(spaces, out.count)
            if removable > 0 { out.removeLast(removable) }
            out += "<br>\n"
        } else {
            out += "\n"
        }
        index += 1
    }

    func runLength(at start: Int, of character: Character) -> Int {
        var length = 0
        while start + length < end && chars[start + length] == character {
            length += 1
        }
        return length
    }

    // MARK: Code spans

    mutating func parseCode() {
        let run = runLength(at: index, of: "`")
        guard run > 0 else { return }
        var scan = index + run
        while scan < end {
            if chars[scan] == "`" {
                let closing = runLength(at: scan, of: "`")
                if closing == run {
                    var content = String(chars[(index + run)..<scan])
                    if content.count >= 2,
                       content.hasPrefix(" "),
                       content.hasSuffix(" "),
                       content.contains(where: { $0 != " " }) {
                        content.removeFirst()
                        content.removeLast()
                    }
                    out += "<code>" + MDRUtil.escape(content) + "</code>"
                    index = scan + run
                    return
                }
                scan += closing
            } else {
                scan += 1
            }
        }
        out += String(repeating: "`", count: run)
        index += run
    }

    // MARK: Brackets

    func findClosingBracket(from start: Int) -> Int? {
        var scan = start
        var depth = 0
        while scan < end {
            let character = chars[scan]
            if character == "\\" {
                scan += 2
                continue
            }
            if character == "`" {
                let run = runLength(at: scan, of: "`")
                var probe = scan + run
                var found = false
                while probe < end {
                    if chars[probe] == "`" {
                        let closing = runLength(at: probe, of: "`")
                        if closing == run {
                            scan = probe + run
                            found = true
                            break
                        }
                        probe += closing
                    } else {
                        probe += 1
                    }
                }
                if found { continue }
                scan += run
                continue
            }
            if character == "[" {
                depth += 1
                scan += 1
                continue
            }
            if character == "]" {
                if depth == 0 { return scan }
                depth -= 1
                scan += 1
                continue
            }
            scan += 1
        }
        return nil
    }

    struct InlineDestination {
        let destination: String
        let title: String?
        let next: Int
    }

    func parseInlineDestination(from parenIndex: Int) -> InlineDestination? {
        guard parenIndex < end, chars[parenIndex] == "(" else { return nil }
        var scan = parenIndex + 1
        while scan < end && (chars[scan] == " " || chars[scan] == "\t" || chars[scan] == "\n") {
            scan += 1
        }

        var destination = ""
        if scan < end && chars[scan] == "<" {
            scan += 1
            while scan < end && chars[scan] != ">" {
                if chars[scan] == "\\" && scan + 1 < end {
                    destination.append(chars[scan + 1])
                    scan += 2
                    continue
                }
                destination.append(chars[scan])
                scan += 1
            }
            guard scan < end else { return nil }
            scan += 1
        } else {
            var depth = 0
            while scan < end {
                let character = chars[scan]
                if character == "\\" && scan + 1 < end {
                    destination.append(chars[scan + 1])
                    scan += 2
                    continue
                }
                if character == "(" {
                    depth += 1
                    destination.append(character)
                    scan += 1
                    continue
                }
                if character == ")" {
                    if depth == 0 { break }
                    depth -= 1
                    destination.append(character)
                    scan += 1
                    continue
                }
                if character == " " || character == "\t" || character == "\n" { break }
                destination.append(character)
                scan += 1
            }
        }

        while scan < end && (chars[scan] == " " || chars[scan] == "\t" || chars[scan] == "\n") {
            scan += 1
        }

        var title: String?
        if scan < end && (chars[scan] == "\"" || chars[scan] == "'" || chars[scan] == "(") {
            let opener = chars[scan]
            let closer: Character = opener == "(" ? ")" : opener
            scan += 1
            var collected = ""
            while scan < end && chars[scan] != closer {
                if chars[scan] == "\\" && scan + 1 < end {
                    collected.append(chars[scan + 1])
                    scan += 2
                    continue
                }
                collected.append(chars[scan])
                scan += 1
            }
            guard scan < end else { return nil }
            scan += 1
            title = collected
        }

        while scan < end && (chars[scan] == " " || chars[scan] == "\t" || chars[scan] == "\n") {
            scan += 1
        }
        guard scan < end, chars[scan] == ")" else { return nil }
        return InlineDestination(destination: destination, title: title, next: scan + 1)
    }

    // MARK: Links, images, wikilinks

    mutating func parseLink() -> Bool {
        guard let close = findClosingBracket(from: index + 1) else { return false }
        let label = String(chars[(index + 1)..<close])
        var after = close + 1
        var destination: String?
        var title: String?

        if after < end && chars[after] == "(" {
            guard let parsed = parseInlineDestination(from: after) else { return false }
            destination = parsed.destination
            title = parsed.title
            after = parsed.next
        } else if after < end && chars[after] == "[" {
            guard let close2 = findClosingBracket(from: after + 1) else { return false }
            var identifier = String(chars[(after + 1)..<close2])
            if identifier.isEmpty { identifier = label }
            guard let reference = refs[MDRUtil.normalizeLabel(identifier)] else { return false }
            destination = reference.url
            title = reference.title
            after = close2 + 1
        } else if let reference = refs[MDRUtil.normalizeLabel(label)] {
            destination = reference.url
            title = reference.title
        } else {
            return false
        }

        let inner = MDRUtil.renderInline(label, refs: refs, basePath: basePath, depth: depth + 1)
        if let raw = destination, let safe = MDRUtil.sanitizedURL(raw, isImage: false, basePath: nil) {
            var html = "<a href=\"" + MDRUtil.escape(safe) + "\""
            if let title, !title.isEmpty {
                html += " title=\"" + MDRUtil.escape(title) + "\""
            }
            html += ">" + inner + "</a>"
            out += html
        } else {
            out += inner
        }
        index = after
        return true
    }

    mutating func parseImage() -> Bool {
        let openBracket = index + 1
        guard let close = findClosingBracket(from: openBracket + 1) else { return false }
        let label = String(chars[(openBracket + 1)..<close])
        var after = close + 1
        var destination: String?
        var title: String?

        if after < end && chars[after] == "(" {
            guard let parsed = parseInlineDestination(from: after) else { return false }
            destination = parsed.destination
            title = parsed.title
            after = parsed.next
        } else if after < end && chars[after] == "[" {
            guard let close2 = findClosingBracket(from: after + 1) else { return false }
            var identifier = String(chars[(after + 1)..<close2])
            if identifier.isEmpty { identifier = label }
            guard let reference = refs[MDRUtil.normalizeLabel(identifier)] else { return false }
            destination = reference.url
            title = reference.title
            after = close2 + 1
        } else if let reference = refs[MDRUtil.normalizeLabel(label)] {
            destination = reference.url
            title = reference.title
        } else {
            return false
        }

        guard let raw = destination else { return false }
        if let safe = MDRUtil.sanitizedURL(raw, isImage: true, basePath: basePath) {
            var html = "<img src=\"" + MDRUtil.escape(safe) + "\" alt=\"" + MDRUtil.escape(label) + "\""
            if let title, !title.isEmpty {
                html += " title=\"" + MDRUtil.escape(title) + "\""
            }
            html += ">"
            out += html
        } else {
            out += MDRUtil.escape(label)
        }
        index = after
        return true
    }

    mutating func parseWikilink() -> Bool {
        var scan = index + 2
        while scan + 1 < end {
            if chars[scan] == "]" && chars[scan + 1] == "]" {
                let inner = String(chars[(index + 2)..<scan])
                out += "<span class=\"wikilink\">" + MDRUtil.escape(inner) + "</span>"
                index = scan + 2
                return true
            }
            scan += 1
        }
        return false
    }

    mutating func parseAutolink() -> Bool {
        var scan = index + 1
        while scan < end && chars[scan] != ">" && chars[scan] != "\n" && chars[scan] != "<" {
            scan += 1
        }
        guard scan < end, chars[scan] == ">" else { return false }
        let inner = String(chars[(index + 1)..<scan])
        guard !inner.isEmpty, !inner.contains(" ") else { return false }

        if inner.contains("@"), !inner.contains(":"), !inner.contains("/") {
            out += "<a href=\"mailto:" + MDRUtil.escape(inner) + "\">" + MDRUtil.escape(inner) + "</a>"
            index = scan + 1
            return true
        }
        guard let safe = MDRUtil.sanitizedURL(inner, isImage: false, basePath: nil) else { return false }
        let lower = inner.lowercased()
        let isAbsolute = lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("mailto:") || lower.hasPrefix("file:") || lower.hasPrefix("ftp://")
        guard isAbsolute else { return false }
        out += "<a href=\"" + MDRUtil.escape(safe) + "\">" + MDRUtil.escape(inner) + "</a>"
        index = scan + 1
        return true
    }

    mutating func parseBareURL() -> Bool {
        var literal: [Character]?
        for candidate in MDRUtil.urlLiterals where MDRUtil.matchesCaseInsensitive(chars, at: index, candidate) {
            literal = candidate
            break
        }
        guard let literal else { return false }

        var scan = index
        while scan < end {
            let character = chars[scan]
            if character.isWhitespace || character == "<" || character == ">" || character == "\"" {
                break
            }
            scan += 1
        }
        let raw = MDRUtil.trimTrailingURLPunctuation(String(chars[index..<scan]))
        guard raw.count > literal.count else { return false }
        guard let safe = MDRUtil.sanitizedURL(raw, isImage: false, basePath: nil) else { return false }

        let href = literal == MDRUtil.wwwLiteral ? "http://" + safe : safe
        out += "<a href=\"" + MDRUtil.escape(href) + "\">" + MDRUtil.escape(raw) + "</a>"
        index += raw.count
        return true
    }

    // MARK: Tags, highlight, strikethrough, emphasis

    mutating func parseTag() -> Bool {
        if index > 0, MDRUtil.isWordCharacter(chars[index - 1]) { return false }
        var scan = index + 1
        guard scan < end, chars[scan].isLetter else { return false }
        var name = "#"
        while scan < end {
            let character = chars[scan]
            if character.isLetter || character.isNumber || character == "_" || character == "-" || character == "/" {
                name.append(character)
                scan += 1
            } else {
                break
            }
        }
        while name.count > 1, name.hasSuffix("/") {
            name.removeLast()
        }
        guard name.count > 1 else { return false }
        out += "<span class=\"tag\">" + MDRUtil.escape(name) + "</span>"
        index = scan
        return true
    }

    mutating func parseHighlight() -> Bool {
        guard index + 1 < end, chars[index] == "=", chars[index + 1] == "=" else { return false }
        var scan = index + 2
        while scan + 1 < end {
            if chars[scan] == "=" && chars[scan + 1] == "=" { break }
            scan += 1
        }
        guard scan + 1 < end else { return false }
        let inner = String(chars[(index + 2)..<scan])
        guard !inner.isEmpty else { return false }
        let rendered = MDRUtil.renderInline(inner, refs: refs, basePath: basePath, depth: depth + 1)
        out += "<mark>" + rendered + "</mark>"
        index = scan + 2
        return true
    }

    mutating func parseStrikethrough() -> Bool {
        guard index + 1 < end, chars[index] == "~", chars[index + 1] == "~" else { return false }
        var scan = index + 2
        while scan + 1 < end {
            if chars[scan] == "~" && chars[scan + 1] == "~" { break }
            scan += 1
        }
        guard scan + 1 < end else { return false }
        let inner = String(chars[(index + 2)..<scan])
        guard !inner.isEmpty else { return false }
        let rendered = MDRUtil.renderInline(inner, refs: refs, basePath: basePath, depth: depth + 1)
        out += "<del>" + rendered + "</del>"
        index = scan + 2
        return true
    }

    mutating func parseEmphasis() -> Bool {
        let marker = chars[index]
        let run = runLength(at: index, of: marker)

        if marker == "_" {
            if index > 0, MDRUtil.isWordCharacter(chars[index - 1]) { return false }
            if index + run < end, chars[index + run].isWhitespace { return false }
        }

        let wanted = run >= 3 ? 3 : (run >= 2 ? 2 : 1)
        let contentStart = index + wanted
        if contentStart < end, chars[contentStart].isWhitespace { return false }
        guard let close = findClosingEmphasis(marker: marker, length: wanted, from: contentStart) else {
            return false
        }
        let inner = String(chars[contentStart..<close])
        guard !inner.isEmpty else { return false }
        let rendered = MDRUtil.renderInline(inner, refs: refs, basePath: basePath, depth: depth + 1)

        switch wanted {
        case 3: out += "<strong><em>" + rendered + "</em></strong>"
        case 2: out += "<strong>" + rendered + "</strong>"
        default: out += "<em>" + rendered + "</em>"
        }
        index = close + wanted
        return true
    }

    func findClosingEmphasis(marker: Character, length: Int, from start: Int) -> Int? {
        var scan = start
        while scan < end {
            if chars[scan] == "\\" {
                scan += 2
                continue
            }
            if chars[scan] == marker {
                let run = runLength(at: scan, of: marker)
                if run == length {
                    if scan > 0, chars[scan - 1].isWhitespace {
                        scan += run
                        continue
                    }
                    if marker == "_", scan + run < end, MDRUtil.isWordCharacter(chars[scan + run]) {
                        scan += run
                        continue
                    }
                    return scan
                }
                scan += run
                continue
            }
            scan += 1
        }
        return nil
    }
}

// MARK: - Colours

private struct MDRColor {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: String) {
        let cleaned = hex.filter { $0.isHexDigit }
        var value: UInt64 = 0
        _ = Scanner(string: String(cleaned)).scanHexInt64(&value)
        switch cleaned.count {
        case 3:
            self.init(
                red: Double((value >> 8) & 0xF) / 15.0,
                green: Double((value >> 4) & 0xF) / 15.0,
                blue: Double(value & 0xF) / 15.0
            )
        case 8:
            self.init(
                red: Double((value >> 24) & 0xFF) / 255.0,
                green: Double((value >> 16) & 0xFF) / 255.0,
                blue: Double((value >> 8) & 0xFF) / 255.0
            )
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0
            )
        default:
            self.init(red: 0, green: 0, blue: 0)
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    var hexString: String {
        let r = Int((clamped(red) * 255).rounded())
        let g = Int((clamped(green) * 255).rounded())
        let b = Int((clamped(blue) * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    func rgba(_ alpha: Double) -> String {
        let r = Int((clamped(red) * 255).rounded())
        let g = Int((clamped(green) * 255).rounded())
        let b = Int((clamped(blue) * 255).rounded())
        let a = String(format: "%.2f", min(1, max(0, alpha)))
        return "rgba(\(r), \(g), \(b), \(a))"
    }

    func mixed(with other: MDRColor, amount: Double) -> MDRColor {
        let t = min(1, max(0, amount))
        return MDRColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    func scaled(by factor: Double) -> MDRColor {
        MDRColor(red: clamped(red * factor), green: clamped(green * factor), blue: clamped(blue * factor))
    }
}

private struct MDRPalette {
    let background: MDRColor
    let text: MDRColor
    let secondaryText: MDRColor
    let heading: MDRColor
    let link: MDRColor
    let tag: MDRColor
    let quote: MDRColor
    let codeText: MDRColor
    let codeBackground: MDRColor
    let elevated: MDRColor
    let selection: MDRColor
    let border: MDRColor
    let isDark: Bool

    init(theme: Theme) {
        background = MDRColor(hex: theme.background)
        text = MDRColor(hex: theme.text)
        secondaryText = MDRColor(hex: theme.secondaryText)
        heading = MDRColor(hex: theme.heading)
        link = MDRColor(hex: theme.link)
        tag = MDRColor(hex: theme.tag)
        quote = MDRColor(hex: theme.quote)
        codeText = MDRColor(hex: theme.codeText)
        codeBackground = MDRColor(hex: theme.codeBackground)
        elevated = MDRColor(hex: theme.elevated)
        selection = MDRColor(hex: theme.selection)
        border = MDRColor(hex: theme.border)
        isDark = theme.isDark
    }

    /// `theme.elevated` blended towards the page background, then nudged so a code
    /// block keeps a visible edge even when the palette is very low contrast.
    var codeBlockBackground: MDRColor {
        let base = codeBackground.mixed(with: elevated, amount: 0.5)
        return isDark
            ? base.mixed(with: MDRColor(hex: "#ffffff"), amount: 0.05)
            : base.mixed(with: MDRColor(hex: "#000000"), amount: 0.02)
    }

    var softBorder: MDRColor { border }

    /// The table card sits slightly above the page, like a code block but lighter.
    var tableBackground: MDRColor { background.mixed(with: elevated, amount: isDark ? 0.75 : 0.55) }
    var tableHeaderBackground: MDRColor {
        isDark ? elevated.mixed(with: MDRColor(hex: "#ffffff"), amount: 0.05)
               : elevated.mixed(with: MDRColor(hex: "#000000"), amount: 0.04)
    }
    var tableRowBackground: String { text.rgba(isDark ? 0.028 : 0.022) }
    var tableRowHover: String { text.rgba(isDark ? 0.055 : 0.04) }
    var tableGrid: MDRColor { border.mixed(with: secondaryText, amount: 0.28) }
    var wikilinkBackground: MDRColor { background.mixed(with: link, amount: 0.12) }
    var highlightColor: String {
        isDark ? "rgba(255, 214, 10, 0.26)" : "rgba(255, 214, 10, 0.42)"
    }
    var scrollbarThumb: MDRColor { border.mixed(with: secondaryText, amount: 0.35) }
}

// MARK: - Stylesheet

private enum MDRStylesheet {

    static func sanitizedFontCSS(_ fontCSS: String) -> String {
        var out = ""
        for character in fontCSS {
            switch character {
            case "\n", "\r", "<", ">", "{", "}": continue
            default: out.append(character)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func build(theme: Theme, fontCSS: String) -> String {
        let palette = MDRPalette(theme: theme)
        let font = sanitizedFontCSS(fontCSS)

        var parts: [String] = []

        parts.append("""
        /* Mishka markdown preview */
        * { box-sizing: border-box; }
        html { -webkit-text-size-adjust: 100%; }
        body {
          margin: 0;
          background: \(palette.background.hexString);
        }
        .markdown-body {
          max-width: 46rem;
          margin: 0 auto;
          padding: 3rem 2.5rem 6rem;
          background: \(palette.background.hexString);
          color: \(palette.text.hexString);
          \(font)
          line-height: 1.65;
          overflow-wrap: break-word;
          -webkit-font-smoothing: antialiased;
          text-rendering: optimizeLegibility;
        }
        .markdown-body > *:first-child { margin-top: 0; }
        .markdown-body > *:last-child { margin-bottom: 0; }
        .markdown-body p { margin: 0 0 1.15em; }
        .markdown-body strong { font-weight: 700; }
        .markdown-body em { font-style: italic; }
        .markdown-body del { color: \(palette.secondaryText.hexString); text-decoration: line-through; }
        .markdown-body a { color: \(palette.link.hexString); text-decoration: none; }
        .markdown-body a:hover { text-decoration: underline; text-underline-offset: 0.15em; }
        """)

        parts.append("""
        .markdown-body h1,
        .markdown-body h2,
        .markdown-body h3,
        .markdown-body h4,
        .markdown-body h5,
        .markdown-body h6 {
          color: \(palette.heading.hexString);
          font-weight: 700;
          line-height: 1.25;
          margin: 2.1em 0 0.7em;
          letter-spacing: -0.011em;
        }
        .markdown-body h1 { font-size: 2.05em; line-height: 1.15; letter-spacing: -0.022em; margin-top: 1.25em; }
        .markdown-body h2 { font-size: 1.55em; letter-spacing: -0.016em; }
        .markdown-body h3 { font-size: 1.28em; }
        .markdown-body h4 { font-size: 1.12em; }
        .markdown-body h5 { font-size: 1em; }
        .markdown-body h6 { font-size: 0.92em; font-weight: 600; }
        """)

        parts.append("""
        .markdown-body code,
        .markdown-body pre,
        .markdown-body kbd {
          font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
        }
        .markdown-body code {
          background: \(palette.codeBackground.hexString);
          color: \(palette.codeText.hexString);
          padding: 0.14em 0.38em;
          border-radius: 6px;
          font-size: 0.89em;
        }
        .markdown-body pre {
          background: \(palette.codeBlockBackground.hexString);
          color: \(palette.codeText.hexString);
          border: 1px solid \(palette.softBorder.rgba(0.55));
          border-radius: 10px;
          padding: 1rem 1.15rem;
          margin: 0 0 1.35em;
          overflow-x: auto;
          overflow-y: hidden;
          line-height: 1.5;
          -webkit-overflow-scrolling: touch;
        }
        .markdown-body pre code {
          display: block;
          background: transparent;
          color: inherit;
          border-radius: 0;
          padding: 0;
          font-size: 0.88em;
          white-space: pre;
          word-break: normal;
          overflow-wrap: normal;
        }
        """)

        parts.append("""
        .markdown-body blockquote {
          margin: 0 0 1.35em;
          padding: 0.15em 0 0.15em 1.15em;
          border-left: 3px solid \(palette.quote.hexString);
          color: \(palette.secondaryText.hexString);
        }
        .markdown-body blockquote > :last-child { margin-bottom: 0; }
        .markdown-body hr {
          border: 0;
          border-top: 1px solid \(palette.border.hexString);
          margin: 2.4em 0;
        }
        .markdown-body .tag { color: \(palette.tag.hexString); font-weight: 600; }
        .markdown-body .wikilink {
          color: \(palette.link.hexString);
          background: \(palette.wikilinkBackground.rgba(0.55));
          border-radius: 4px;
          padding: 0.05em 0.3em;
          font-weight: 500;
        }
        .markdown-body mark {
          background: \(palette.highlightColor);
          color: inherit;
          border-radius: 3px;
          padding: 0.05em 0.2em;
        }
        """)

        parts.append("""
        .markdown-body ul,
        .markdown-body ol { margin: 0 0 1.15em; padding-left: 1.6em; }
        .markdown-body li { margin: 0.28em 0; }
        .markdown-body li > ul,
        .markdown-body li > ol { margin: 0.3em 0 0.4em; }
        .markdown-body ul { list-style-type: disc; }
        .markdown-body ul ul { list-style-type: circle; }
        .markdown-body ul ul ul { list-style-type: square; }
        .markdown-body li:has(> input[type="checkbox"]) { list-style: none; margin-left: -1.45em; }
        .markdown-body input[type="checkbox"] {
          -webkit-appearance: none;
          appearance: none;
          width: 1em;
          height: 1em;
          margin: 0 0.5em 0 0;
          border: 1.5px solid \(palette.border.hexString);
          border-radius: 4px;
          background: transparent;
          vertical-align: -0.12em;
          position: relative;
        }
        .markdown-body input[type="checkbox"]:checked {
          background: \(palette.link.hexString);
          border-color: \(palette.link.hexString);
        }
        .markdown-body input[type="checkbox"]:checked::after {
          content: "";
          position: absolute;
          left: 0.28em;
          top: 0.08em;
          width: 0.3em;
          height: 0.56em;
          border: solid \(palette.background.hexString);
          border-width: 0 2px 2px 0;
          transform: rotate(45deg);
        }
        .markdown-body .front-matter {
          display: flex;
          flex-wrap: wrap;
          gap: 0.4em 1.6em;
          margin: 0 0 1.6em;
          padding: 0.75em 1em;
          border: 1px solid \(palette.border.hexString);
          border-radius: 10px;
          background: \(palette.tableBackground.hexString);
          font-size: 0.86em;
          line-height: 1.5;
        }
        .markdown-body .front-matter .fm-key {
          color: \(palette.secondaryText.hexString);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          font-size: 0.92em;
          font-weight: 600;
          margin-right: 0.5em;
        }
        .markdown-body .front-matter .fm-value {
          color: \(palette.text.hexString);
          font-variant-numeric: tabular-nums;
        }
        .markdown-body .table-scroll {
          margin: 0 0 1.5em;
          max-width: 100%;
          overflow-x: auto;
          overflow-y: hidden;
        }
        .markdown-body .table-wrap {
          display: block;
          width: fit-content;
          border: 1px solid \(palette.border.hexString);
          border-radius: 10px;
          background: \(palette.tableBackground.hexString);
          overflow: hidden;
        }
        .markdown-body table {
          border-collapse: separate;
          border-spacing: 0;
          /* Columns size themselves to their content instead of stretching
             across the page; wide tables are capped and scrolled by the wrapper. */
          width: auto;
          max-width: none;
          margin: 0;
          font-size: 0.925em;
          line-height: 1.45;
          font-variant-numeric: tabular-nums;
        }
        .markdown-body th,
        .markdown-body td {
          border: 0;
          padding: 0.38em 0.85em;
          vertical-align: middle;
          min-width: 2.2em;
        }
        .markdown-body th:first-child,
        .markdown-body td:first-child { padding-left: 1.05em; }
        .markdown-body th:last-child,
        .markdown-body td:last-child { padding-right: 1.05em; }
        .markdown-body thead th {
          background: \(palette.tableHeaderBackground.hexString);
          color: \(palette.heading.hexString);
          font-weight: 620;
          font-size: 0.93em;
          letter-spacing: 0.01em;
          padding-top: 0.5em;
          padding-bottom: 0.5em;
          border-bottom: 1px solid \(palette.tableGrid.hexString);
          white-space: nowrap;
        }
        .markdown-body tbody td {
          border-bottom: 1px solid \(palette.tableGrid.rgba(0.5));
        }
        .markdown-body thead tr:first-child th:first-child { border-top-left-radius: 9px; }
        .markdown-body thead tr:first-child th:last-child { border-top-right-radius: 9px; }
        .markdown-body tbody tr:last-child td:first-child { border-bottom-left-radius: 9px; }
        .markdown-body tbody tr:last-child td:last-child { border-bottom-right-radius: 9px; }
        .markdown-body tbody tr:nth-child(even) td {
          background: \(palette.tableRowBackground);
        }
        .markdown-body tbody tr:hover td {
          background: \(palette.tableRowHover);
        }
        .markdown-body tbody tr:last-child td {
          border-bottom: 0;
        }
        .markdown-body th > *:first-child,
        .markdown-body td > *:first-child { margin-top: 0; }
        .markdown-body th > *:last-child,
        .markdown-body td > *:last-child { margin-bottom: 0; }
        .markdown-body td p,
        .markdown-body th p { margin: 0; }
        .markdown-body img { max-width: 100%; height: auto; border-radius: 8px; }
        """)

        parts.append("""
        .markdown-body ::selection,
        body ::selection { background: \(palette.selection.hexString); }
        .markdown-body ::-webkit-scrollbar { width: 11px; height: 11px; }
        .markdown-body ::-webkit-scrollbar-track { background: transparent; }
        .markdown-body ::-webkit-scrollbar-thumb {
          background-color: \(palette.scrollbarThumb.hexString);
          border: 3px solid transparent;
          border-radius: 6px;
          background-clip: content-box;
        }
        .markdown-body ::-webkit-scrollbar-thumb:hover {
          background-color: \(palette.secondaryText.hexString);
          background-clip: content-box;
        }
        .markdown-body ::-webkit-scrollbar-corner { background: transparent; }
        @media (max-width: 700px) {
          .markdown-body { padding: 1.6rem 1.15rem 4rem; }
        }
        """)

        return parts.joined(separator: "\n\n")
    }
}
