import AppKit
import SwiftUI

// MARK: - Layout manager: draws bullets and checkboxes in the left gutter

final class MarkdownLayoutManager: NSLayoutManager {

    var theme: Theme = ThemeCatalog.theme(id: ThemeCatalog.defaultID)
    var accent: NSColor = NSColor(hex: "#E8452B")
    var baseFontSize: CGFloat = 15

    /// Horizontal step of one list nesting level. Must match `MarkdownHighlighter`.
    private var step: CGFloat { (baseFontSize * 1.55).rounded() }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, !textContainers.isEmpty else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        drawTables(storage: storage, charRange: charRange, origin: origin)
        drawListGutters(storage: storage, charRange: charRange, origin: origin)
    }

    // MARK: - Tables

    /// Draws the rounded "card" behind a GFM table plus its row separators, so a table
    /// typed in plain markdown reads as a real table while you write it.
    private func drawTables(storage: NSTextStorage, charRange: NSRange, origin: NSPoint) {
        var blocks: [NSRange] = []
        storage.enumerateAttribute(.mishkaTableBlock, in: charRange, options: []) { value, _, _ in
            guard let value = value as? NSValue else { return }
            let block = value.rangeValue
            if !blocks.contains(block) { blocks.append(block) }
        }
        for block in blocks {
            drawTable(block: block, storage: storage, origin: origin)
        }
    }

    private func drawTable(block: NSRange, storage: NSTextStorage, origin: NSPoint) {
        let string = storage.string as NSString
        var lines: [(range: NSRange, rect: NSRect, used: NSRect, role: Int)] = []

        var location = block.location
        let end = NSMaxRange(block)
        while location < end {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            let glyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
            if glyphs.length > 0 {
                let rect = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let used = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let role = storage.attribute(.mishkaTableRole, at: paragraph.location, effectiveRange: nil) as? Int ?? 2
                lines.append((paragraph, rect, used, role))
            }
            let next = NSMaxRange(paragraph)
            if next <= location { break }
            location = next
        }

        guard let first = lines.first else { return }

        // The card hugs the widest row, so the columns size themselves to their content
        // instead of stretching across the whole editor.
        let inset = MarkdownHighlighter.tableInset
        var minY = first.rect.minY
        var maxY = first.rect.maxY
        var contentMinX = min(first.rect.minX, first.used.minX)
        var contentMaxX = first.used.maxX
        for line in lines {
            minY = min(minY, line.rect.minY)
            maxY = max(maxY, line.rect.maxY)
            contentMinX = min(contentMinX, min(line.rect.minX, line.used.minX))
            contentMaxX = max(contentMaxX, line.used.maxX)
        }

        let padding: CGFloat = 5
        let left = max(0, contentMinX - inset)
        let card = NSRect(
            x: origin.x + left,
            y: origin.y + minY - padding,
            width: max(90, contentMaxX - left + inset),
            height: (maxY - minY) + padding * 2
        )
        guard card.width > 1, card.height > 1 else { return }

        let fill = NSColor(hex: theme.elevated).blended(with: NSColor(hex: theme.background), amount: 0.45)
        let borderColor = NSColor(hex: theme.border)
        let gridColor = borderColor.blended(with: NSColor(hex: theme.secondaryText), amount: 0.25)

        let cardPath = NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8)
        fill.setFill()
        cardPath.fill()
        borderColor.setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        // Header rule, then a hairline between every pair of body rows.
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            if line.role == 1 {
                hairline(
                    y: origin.y + line.rect.maxY,
                    from: card.minX,
                    to: card.maxX,
                    color: gridColor
                )
            } else if line.role >= 2, !isLast {
                hairline(
                    y: origin.y + line.rect.maxY,
                    from: card.minX,
                    to: card.maxX,
                    color: borderColor.withAlphaComponent(0.7)
                )
            }
        }
    }

    private func hairline(y: CGFloat, from x0: CGFloat, to x1: CGFloat, color: NSColor) {
        guard x1 > x0 else { return }
        color.setFill()
        NSBezierPath(rect: NSRect(x: x0, y: y - 0.5, width: x1 - x0, height: 1)).fill()
    }

    // MARK: - List gutters

    private func drawListGutters(storage: NSTextStorage, charRange: NSRange, origin: NSPoint) {
        let string = storage.string as NSString

        storage.enumerateAttributes(in: charRange, options: []) { attributes, range, _ in
            let task = attributes[.mishkaTask] as? Int
            let bullet = attributes[.mishkaBullet] as? Int
            guard task != nil || bullet != nil else { return }

            let indent = attributes[.mishkaIndent] as? Int ?? 1
            let paragraph = string.paragraphRange(for: NSRange(location: range.location, length: 0))
            let glyphRange = self.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let lineRect = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            guard lineRect.height > 0 else { return }

            let gutterX = origin.x + lineRect.minX + self.step * CGFloat(max(0, indent - 1))
            let centerY = origin.y + lineRect.minY + lineRect.height / 2

            if let task {
                self.drawCheckbox(
                    in: NSRect(
                        x: gutterX + 1.5,
                        y: centerY - self.checkboxSize / 2,
                        width: self.checkboxSize,
                        height: self.checkboxSize
                    ),
                    checked: task == 1
                )
            } else if bullet != nil {
                self.drawBullet(centerX: gutterX + self.step * 0.40, centerY: centerY)
            }
        }
    }

    private var checkboxSize: CGFloat { (baseFontSize * 0.94).rounded() }

    private func drawCheckbox(in rect: NSRect, checked: Bool) {
        let radius = rect.height * 0.30
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: radius, yRadius: radius)

        if checked {
            accent.setFill()
            path.fill()

            // Checkmark, drawn slightly inset so it never touches the border.
            let mark = NSBezierPath()
            let x0 = rect.minX + rect.width * 0.25
            let x1 = rect.minX + rect.width * 0.43
            let x2 = rect.minX + rect.width * 0.76
            let y0 = rect.minY + rect.height * 0.52
            let y1 = rect.minY + rect.height * 0.30
            let y2 = rect.minY + rect.height * 0.72
            mark.move(to: NSPoint(x: x0, y: y0))
            mark.line(to: NSPoint(x: x1, y: y1))
            mark.line(to: NSPoint(x: x2, y: y2))
            mark.lineWidth = max(1.4, rect.height * 0.13)
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            NSColor(hex: theme.background).setStroke()
            mark.stroke()
        } else {
            NSColor(hex: theme.marker).setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }
    }

    private func drawBullet(centerX: CGFloat, centerY: CGFloat) {
        let radius = max(1.7, baseFontSize * 0.155)
        let rect = NSRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
        NSColor(hex: theme.secondaryText).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}

// MARK: - Text view: click handling, list continuation, indentation

final class MarkdownTextView: NSTextView {

    var highlightEngine: MarkdownHighlighter?
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((NSRange) -> Void)?
    var onToggleTask: ((String) -> Void)?
    var focusMode: Bool = false
    /// Maximum width of the centred text column.
    var maxContentWidth: CGFloat = 720

    private var isHighlighting = false
    private var pendingHighlight = false
    private var lastContainerInset: CGFloat = -1
    private var lastRevealParagraph: NSRange = NSRange(location: NSNotFound, length: 0)

    // MARK: Init

    init(theme: Theme, accent: NSColor, typography: EditorTypography) {
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        layoutManager.theme = theme
        layoutManager.accent = accent
        layoutManager.baseFontSize = typography.size
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        super.init(frame: .zero, textContainer: container)

        self.highlightEngine = MarkdownHighlighter(typography: typography, theme: theme, accent: accent)

        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isEditable = true
        isSelectable = true
        drawsBackground = true
        backgroundColor = NSColor(hex: theme.background)
        insertionPointColor = accent
        selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.selection)]
        textContainerInset = NSSize(width: 28, height: 26)
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        // Markdown must never be "corrected" by the system.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false
        isContinuousSpellCheckingEnabled = false
        allowsImageEditing = false
        isGrammarCheckingEnabled = false

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        font = typography.baseFont()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — the editor is created programmatically")
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Appearance

    func apply(theme: Theme, accent: NSColor, typography: EditorTypography) {
        guard let engine = highlightEngine else { return }
        engine.theme = theme
        engine.accent = accent
        engine.typography = typography
        if let layoutManager = layoutManager as? MarkdownLayoutManager {
            layoutManager.theme = theme
            layoutManager.accent = accent
            layoutManager.baseFontSize = typography.size
        }
        backgroundColor = NSColor(hex: theme.background)
        insertionPointColor = accent
        selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.selection)]
        font = typography.baseFont()
        refreshHighlight()
    }

    // MARK: Centred column

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerInset()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateContainerInset()
    }

    private func updateContainerInset() {
        let available = enclosingScrollView?.contentSize.width ?? bounds.width
        let side = max(26, ((available - maxContentWidth) / 2).rounded())
        guard abs(side - lastContainerInset) > 0.5 else { return }
        lastContainerInset = side
        textContainerInset = NSSize(width: side, height: 26)
    }

    // MARK: Highlighting

    func refreshHighlight() {
        guard let engine = highlightEngine, let storage = textStorage else { return }
        if isHighlighting {
            pendingHighlight = true
            return
        }
        isHighlighting = true
        let selection = selectedRange()
        lastRevealParagraph = (storage.string as NSString).paragraphRange(for: selection)
        let paragraph = focusMode ? (string as NSString).paragraphRange(for: selection) : nil
        engine.highlight(storage, selection: selection)
        if let paragraph {
            engine.applyFocusDim(storage, keeping: paragraph)
        }
        isHighlighting = false
        if pendingHighlight {
            pendingHighlight = false
            DispatchQueue.main.async { [weak self] in self?.refreshHighlight() }
        }
    }

    override func didChangeText() {
        super.didChangeText()
        refreshHighlight()
        onTextChange?(string)
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        onSelectionChange?(charRange)
        // Syntax markers are revealed per paragraph, and focused mode dims per paragraph,
        // so a full re-highlight is only needed when the caret actually changes paragraph.
        let paragraph = (string as NSString).paragraphRange(for: charRange)
        if paragraph != lastRevealParagraph {
            lastRevealParagraph = paragraph
            refreshHighlight()
        }
    }

    // MARK: Gutter clicks

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), openLink(at: event) { return }
        if handleGutterClick(event) { return }
        super.mouseDown(with: event)
    }

    private func openLink(at event: NSEvent) -> Bool {
        guard let layoutManager, let container = textContainer, let storage = textStorage else { return false }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: viewPoint.y - textContainerInset.height
        )
        let index = layoutManager.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard index < storage.length else { return false }
        guard let value = storage.attribute(.link, at: index, effectiveRange: nil) else { return false }
        let string = value as? String
        guard let string, let url = URL(string: string) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    private func handleGutterClick(_ event: NSEvent) -> Bool {
        guard let layoutManager = layoutManager as? MarkdownLayoutManager,
              let container = textContainer,
              let storage = textStorage else { return false }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: viewPoint.y - textContainerInset.height
        )
        let index = layoutManager.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        let string = storage.string as NSString
        guard index < string.length else { return false }
        let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
        guard let task = storage.attribute(.mishkaTask, at: paragraph.location, effectiveRange: nil) as? Int else {
            return false
        }
        _ = task

        let glyphRange = layoutManager.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return false }
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let indent = storage.attribute(.mishkaIndent, at: paragraph.location, effectiveRange: nil) as? Int ?? 1
        let step = (font?.pointSize ?? 15) * 1.55
        let gutterStart = lineRect.minX + step * CGFloat(max(0, indent - 1))
        let gutterEnd = lineRect.minX + step * CGFloat(indent)

        guard containerPoint.x >= gutterStart, containerPoint.x <= gutterEnd + 2 else { return false }

        toggleTask(in: paragraph)
        return true
    }

    /// Flips `[ ]` ⇄ `[x]` in the given paragraph using the regular undo-managed path.
    func toggleTask(in paragraph: NSRange) {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let paragraphText = string.substring(with: paragraph)
        guard let bracketRange = MarkdownHighlighter.taskBracketRange(in: paragraphText as NSString) else { return }
        let absolute = NSRange(location: paragraph.location + bracketRange.location, length: bracketRange.length)
        let current = string.substring(with: absolute)
        let replacement = current == "[ ]" ? "[x]" : "[ ]"

        let previousSelection = selectedRange()
        if shouldChangeText(in: absolute, replacementString: replacement) {
            storage.replaceCharacters(in: absolute, with: replacement)
            didChangeText()
            let restored = NSRange(
                location: min(previousSelection.location, (storage.string as NSString).length),
                length: 0
            )
            setSelectedRange(restored, affinity: .downstream, stillSelecting: false)
        }
    }

    // MARK: Keyboard behaviour

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else {
            super.insertNewline(sender)
            return
        }
        let string = storage.string as NSString
        let paragraph = string.paragraphRange(for: selectedRange())
        let text = string.substring(with: paragraph)

        if let continuation = MarkdownHighlighter.listContinuation(for: text) {
            // Pressing return on an empty item ends the list instead of continuing it.
            if continuation.isEmptyItem {
                let lineContentRange = NSRange(location: paragraph.location, length: continuation.markerLength + continuation.contentLength)
                if shouldChangeText(in: lineContentRange, replacementString: "") {
                    storage.replaceCharacters(in: lineContentRange, with: "")
                    didChangeText()
                }
                return
            }
            let insertion = "\n" + continuation.marker
            let target = selectedRange()
            if shouldChangeText(in: target, replacementString: insertion) {
                storage.replaceCharacters(in: target, with: insertion)
                didChangeText()
                setSelectedRange(
                    NSRange(location: target.location + (insertion as NSString).length, length: 0),
                    affinity: .downstream,
                    stillSelecting: false
                )
            }
            return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if indentSelection(by: 1) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if indentSelection(by: -1) { return }
        super.insertBacktab(sender)
    }

    private func indentSelection(by delta: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let string = storage.string as NSString
        let selection = selectedRange()
        let paragraphRange = string.paragraphRange(for: selection)
        let paragraphs = string.substring(with: paragraphRange)
        let isList = MarkdownHighlighter.isListParagraph(paragraphs)
        guard isList else { return false }

        let lines = paragraphs.components(separatedBy: "\n")
        let updated = lines.map { line -> String in
            if delta > 0 {
                return "  " + line
            }
            if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
            if line.hasPrefix("\t") { return String(line.dropFirst(1)) }
            return line
        }.joined(separator: "\n")

        guard updated != paragraphs else { return true }
        if shouldChangeText(in: paragraphRange, replacementString: updated) {
            storage.replaceCharacters(in: paragraphRange, with: updated)
            didChangeText()
            setSelectedRange(
                NSRange(location: paragraphRange.location, length: (updated as NSString).length),
                affinity: .downstream,
                stillSelecting: false
            )
        }
        return true
    }

    /// ⌘K turns the selection into a link, matching Bear's shortcut.
    func wrapSelectionAsLink() {
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        let selected = (string as NSString).substring(with: selection)
        let replacement = "[\(selected)](url)"
        guard let storage = textStorage, shouldChangeText(in: selection, replacementString: replacement) else { return }
        storage.replaceCharacters(in: selection, with: replacement)
        didChangeText()
        let urlStart = selection.location + (selected as NSString).length + 3
        setSelectedRange(NSRange(location: urlStart, length: 3), affinity: .downstream, stillSelecting: false)
    }
    // MARK: - Formatting commands (driven from the Format menu)

    @objc func toggleBold(_ sender: Any?) { wrapSelection(prefix: "**", suffix: "**") }
    @objc func toggleItalic(_ sender: Any?) { wrapSelection(prefix: "*", suffix: "*") }
    @objc func toggleStrikethrough(_ sender: Any?) { wrapSelection(prefix: "~~", suffix: "~~") }
    @objc func toggleHighlight(_ sender: Any?) { wrapSelection(prefix: "==", suffix: "==") }
    @objc func toggleInlineCode(_ sender: Any?) { wrapSelection(prefix: "`", suffix: "`") }
    @objc func insertLink(_ sender: Any?) { wrapSelectionAsLink() }

    @objc func makeHeading1(_ sender: Any?) { setHeadingLevel(1) }
    @objc func makeHeading2(_ sender: Any?) { setHeadingLevel(2) }
    @objc func makeHeading3(_ sender: Any?) { setHeadingLevel(3) }
    @objc func makePlainParagraph(_ sender: Any?) { setHeadingLevel(0) }

    @objc func toggleTaskList(_ sender: Any?) { toggleLinePrefix("- [ ] ") }
    @objc func toggleBulletList(_ sender: Any?) { toggleLinePrefix("- ") }
    @objc func toggleNumberedList(_ sender: Any?) { toggleLinePrefix("1. ") }
    @objc func toggleQuote(_ sender: Any?) { toggleLinePrefix("> ") }

    /// Wraps or unwraps the selection with a marker pair, toggling on repeated use.
    func wrapSelection(prefix: String, suffix: String) {
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let ns = string as NSString
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length

        guard selection.length > 0 else {
            let insertion = prefix + suffix
            guard shouldChangeText(in: selection, replacementString: insertion) else { return }
            storage.replaceCharacters(in: selection, with: insertion)
            didChangeText()
            setSelectedRange(
                NSRange(location: selection.location + prefixLength, length: 0),
                affinity: .downstream,
                stillSelecting: false
            )
            return
        }

        let selected = ns.substring(with: selection)

        // Case 1: the markers are part of the selection.
        if selected.hasPrefix(prefix), selected.hasSuffix(suffix), selected.count >= prefix.count + suffix.count {
            let inner = (selected as NSString).substring(
                with: NSRange(location: prefixLength, length: (selected as NSString).length - prefixLength - suffixLength)
            )
            replace(selection, with: inner, selecting: NSRange(location: selection.location, length: (inner as NSString).length))
            return
        }

        // Case 2: the markers sit just outside the selection.
        let before = selection.location >= prefixLength
            ? ns.substring(with: NSRange(location: selection.location - prefixLength, length: prefixLength))
            : ""
        let afterEnd = NSMaxRange(selection)
        let after = afterEnd + suffixLength <= ns.length
            ? ns.substring(with: NSRange(location: afterEnd, length: suffixLength))
            : ""
        if before == prefix, after == suffix {
            let outer = NSRange(
                location: selection.location - prefixLength,
                length: selection.length + prefixLength + suffixLength
            )
            replace(outer, with: selected, selecting: NSRange(location: outer.location, length: selection.length))
            return
        }

        // Case 3: wrap it.
        let replacement = prefix + selected + suffix
        replace(selection, with: replacement, selecting: NSRange(location: selection.location + prefixLength, length: selection.length))
    }

    private func replace(_ range: NSRange, with replacement: String, selecting newSelection: NSRange) {
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        let length = (storage.string as NSString).length
        setSelectedRange(
            NSRange(location: min(newSelection.location, length), length: min(newSelection.length, max(0, length - newSelection.location))),
            affinity: .downstream,
            stillSelecting: false
        )
    }

    /// Turns the current line into `# Heading` (level 1…3) or back into a paragraph (0).
    func setHeadingLevel(_ level: Int) {
        guard textStorage != nil else { return }
        let ns = string as NSString
        let paragraph = ns.paragraphRange(for: selectedRange())
        var line = ns.substring(with: paragraph)
        let hadNewline = line.hasSuffix("\n")
        if hadNewline { line.removeLast() }

        var body = line.drop(while: { $0 == "#" })
        body = body.drop(while: { $0 == " " || $0 == "\t" })
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let existingLevel: Int = {
            let hashes = line.drop(while: { $0 == " " || $0 == "\t" }).prefix(while: { $0 == "#" })
            return hashes.isEmpty ? 0 : hashes.count
        }()

        let newLevel = existingLevel == level ? 0 : level
        let prefix = newLevel == 0 ? "" : String(repeating: "#", count: newLevel) + " "
        let updated = indent + prefix + body + (hadNewline ? "\n" : "")
        guard updated != line + (hadNewline ? "\n" : "") else { return }
        replace(paragraph, with: updated, selecting: NSRange(location: paragraph.location + (indent as NSString).length + (prefix as NSString).length, length: 0))
    }

    /// Adds or removes a list/quote prefix on every line of the selection.
    func toggleLinePrefix(_ prefix: String) {
        guard textStorage != nil else { return }
        let ns = string as NSString
        let paragraph = ns.paragraphRange(for: selectedRange())
        let block = ns.substring(with: paragraph)
        let lines = block.components(separatedBy: "\n")

        let allPrefixed = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { line in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                if prefix == "1. " {
                    return MarkdownHighlighter.matchOrdered(String(trimmed)) != nil
                }
                return trimmed.hasPrefix(prefix)
            }

        let updated = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            var body = Substring(line.drop(while: { $0 == " " || $0 == "\t" }))
            if allPrefixed {
                if prefix == "1. ", let match = MarkdownHighlighter.matchOrdered(String(body)) {
                    body = body.dropFirst(match.markerLength)
                } else if body.hasPrefix(prefix) {
                    body = body.dropFirst(prefix.count)
                }
                return indent + String(body)
            }
            return indent + prefix + String(body)
        }.joined(separator: "\n")

        guard updated != block else { return }
        replace(paragraph, with: updated, selecting: NSRange(location: paragraph.location, length: (updated as NSString).length))
    }

}

// MARK: - SwiftUI wrapper

struct MarkdownEditor: NSViewRepresentable {
    let noteID: UUID
    /// The text as it currently exists in the store. The editor never writes through a
    /// binding — every change travels back through `onChange`, so note data has exactly
    /// one owner.
    let text: String
    let theme: Theme
    let accentHex: String
    let typography: EditorTypography
    let focusMode: Bool
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let spellChecking: Bool
    let onChange: (String) -> Void
    let onSelectionChange: (NSRange) -> Void
    let onToggleTask: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(
            theme: theme,
            accent: NSColor(hex: accentHex),
            typography: typography
        )
        textView.delegate = context.coordinator
        textView.onTextChange = { newText in
            context.coordinator.handleTextChange(newText)
        }
        textView.onSelectionChange = { range in
            context.coordinator.parent.onSelectionChange(range)
        }
        textView.maxContentWidth = maxContentWidth
        textView.focusMode = focusMode
        textView.isEditable = isEditable
        textView.isContinuousSpellCheckingEnabled = spellChecking
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.currentNoteID = noteID

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(hex: theme.background)
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        textView.frame = scrollView.contentView.bounds
        textView.refreshHighlight()
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self

        scrollView.backgroundColor = NSColor(hex: theme.background)
        textView.isEditable = isEditable
        textView.maxContentWidth = maxContentWidth
        textView.isContinuousSpellCheckingEnabled = spellChecking

        let needsAppearanceUpdate = context.coordinator.theme != theme
            || context.coordinator.accentHex != accentHex
            || context.coordinator.typography != typography
            || context.coordinator.focusMode != focusMode

        context.coordinator.theme = theme
        context.coordinator.accentHex = accentHex
        context.coordinator.typography = typography
        context.coordinator.focusMode = focusMode

        if needsAppearanceUpdate {
            textView.focusMode = focusMode
            textView.apply(theme: theme, accent: NSColor(hex: accentHex), typography: typography)
        }

        // Switching notes, or an external edit (tag rename, import) replaces the buffer.
        if context.coordinator.currentNoteID != noteID {
            context.coordinator.currentNoteID = noteID
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            // Start the new note with the caret at the top; the previous selection can
            // point past the end of a shorter note.
            textView.setSelectedRange(NSRange(location: 0, length: 0), affinity: .downstream, stillSelecting: false)
            textView.refreshHighlight()
            textView.scroll(.zero)
            context.coordinator.isProgrammaticUpdate = false
        } else if textView.string != text {
            let selection = textView.selectedRange()
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            textView.refreshHighlight()
            let limit = (text as NSString).length
            textView.setSelectedRange(
                NSRange(location: min(selection.location, limit), length: 0),
                affinity: .downstream,
                stillSelecting: false
            )
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: MarkdownTextView?
        var currentNoteID: UUID?
        var isProgrammaticUpdate = false
        var theme: Theme
        var accentHex: String
        var typography: EditorTypography
        var focusMode: Bool

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            self.theme = parent.theme
            self.accentHex = parent.accentHex
            self.typography = parent.typography
            self.focusMode = parent.focusMode
        }

        func handleTextChange(_ newText: String) {
            guard !isProgrammaticUpdate else { return }
            parent.onChange(newText)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            guard !isProgrammaticUpdate else { return }
            parent.onChange(textView.string)
        }

        func textView(
            _ textView: NSTextView,
            clickedOnLink link: Any,
            at charIndex: Int
        ) -> Bool {
            var url: URL?
            if let value = link as? URL {
                url = value
            } else if let value = link as? String {
                url = URL(string: value)
            }
            guard let url else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }
}
