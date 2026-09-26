import SwiftUI

/// A complete colour palette for the whole application: window chrome, note list,
/// sidebar and the markdown editor. Every colour is stored as a `#RRGGBB` string so
/// that themes can be serialised, sent to the HTML preview as CSS and compared cheaply.
struct Theme: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let isDark: Bool

    /// Main editor / preview background.
    let background: String
    /// Sidebar (tags) background.
    let sidebar: String
    /// Note list background.
    let list: String
    /// Cards, code blocks, popovers.
    let elevated: String

    /// Primary text colour.
    let text: String
    /// Secondary text (snippets, metadata).
    let secondaryText: String
    /// Tertiary text (counts, placeholders, dimmed markdown markers).
    let tertiaryText: String

    /// Headings in the editor and in the preview.
    let heading: String
    /// Links.
    let link: String
    /// `#tags`.
    let tag: String
    /// Blockquotes.
    let quote: String

    /// Inline code and fenced code blocks.
    let codeText: String
    let codeBackground: String

    /// Selection highlight in the editor.
    let selection: String
    /// Hairlines and separators.
    let border: String
    /// Dimmed markdown syntax markers (`**`, `#`, `` ` ``, `-` …).
    let marker: String
}

extension Theme {
    /// The default accent colour shipped with the theme. The user may override it
    /// globally, in which case `accent` below wins for every theme.
    var defaultAccent: String { link }
}

// MARK: - Hex helpers

extension Color {
    /// Creates a colour from `#RRGGBB`, `RRGGBB`, `#RGB` or `#RRGGBBAA`.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: Double
        switch cleaned.count {
        case 3: // RGB (12-bit)
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
            a = 1
        case 6: // RRGGBB (24-bit)
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: CGFloat
        switch cleaned.count {
        case 3:
            r = CGFloat((value >> 8) & 0xF) / 15
            g = CGFloat((value >> 4) & 0xF) / 15
            b = CGFloat(value & 0xF) / 15
            a = 1
        case 8:
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        default:
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Multiplies the colour brightness; `1.0` keeps it, `0.9` darkens by 10 %.
    func adjusted(by factor: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        return NSColor(
            srgbRed: min(1, max(0, rgb.redComponent * factor)),
            green: min(1, max(0, rgb.greenComponent * factor)),
            blue: min(1, max(0, rgb.blueComponent * factor)),
            alpha: rgb.alphaComponent
        )
    }

    /// Blends the receiver towards `other`; `amount` is clamped to 0…1.
    func blended(with other: NSColor, amount: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        let t = min(1, max(0, amount))
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}
