import AppKit
import SwiftUI

enum EditorMode: String, CaseIterable, Identifiable, Codable {
    case editor
    case split
    case preview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editor: return "Editor"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }

    var symbol: String {
        switch self {
        case .editor: return "square.and.pencil"
        case .split: return "rectangle.split.2x1"
        case .preview: return "doc.richtext"
        }
    }
}

/// Everything the user can tune, persisted in `UserDefaults`. Kept as plain published
/// properties so SwiftUI views and the AppKit editor both observe the same source of truth.
final class AppSettings: ObservableObject {

    private let defaults = UserDefaults.standard

    @Published var themeID: String { didSet { defaults.set(themeID, forKey: Keys.themeID) } }
    @Published var accentHex: String { didSet { defaults.set(accentHex, forKey: Keys.accentHex) } }
    @Published var followSystemAppearance: Bool { didSet { defaults.set(followSystemAppearance, forKey: Keys.followSystem) } }
    @Published var fontFamily: EditorFontFamily { didSet { defaults.set(fontFamily.rawValue, forKey: Keys.fontFamily) } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) } }
    @Published var maxContentWidth: Double { didSet { defaults.set(maxContentWidth, forKey: Keys.maxWidth) } }
    @Published var focusMode: Bool { didSet { defaults.set(focusMode, forKey: Keys.focusMode) } }
    @Published var spellChecking: Bool { didSet { defaults.set(spellChecking, forKey: Keys.spellChecking) } }
    @Published var showWordCount: Bool { didSet { defaults.set(showWordCount, forKey: Keys.showWordCount) } }
    @Published var sortField: SortField { didSet { defaults.set(sortField.rawValue, forKey: Keys.sortField) } }
    @Published var sortAscending: Bool { didSet { defaults.set(sortAscending, forKey: Keys.sortAscending) } }
    @Published var editorMode: EditorMode { didSet { defaults.set(editorMode.rawValue, forKey: Keys.editorMode) } }
    @Published var sidebarWidth: CGFloat { didSet { defaults.set(Double(sidebarWidth), forKey: Keys.sidebarWidth) } }
    @Published var listWidth: CGFloat { didSet { defaults.set(Double(listWidth), forKey: Keys.listWidth) } }
    @Published var trashRetentionDays: Int { didSet { defaults.set(trashRetentionDays, forKey: Keys.trashRetention) } }

    @Published private(set) var systemIsDark = false

    private enum Keys {
        static let themeID = "themeID"
        static let accentHex = "accentHex"
        static let followSystem = "followSystemAppearance"
        static let fontFamily = "fontFamily"
        static let fontSize = "fontSize"
        static let lineSpacing = "lineSpacing"
        static let maxWidth = "maxContentWidth"
        static let focusMode = "focusMode"
        static let spellChecking = "spellChecking"
        static let showWordCount = "showWordCount"
        static let sortField = "sortField"
        static let sortAscending = "sortAscending"
        static let editorMode = "editorMode"
        static let sidebarWidth = "sidebarWidth"
        static let listWidth = "listWidth"
        static let trashRetention = "trashRetentionDays"
    }

    init() {
        let fallbackTheme = ThemeCatalog.defaultID
        themeID = defaults.string(forKey: Keys.themeID) ?? fallbackTheme
        accentHex = defaults.string(forKey: Keys.accentHex) ?? AccentCatalog.all[0].hex
        followSystemAppearance = defaults.object(forKey: Keys.followSystem) as? Bool ?? true
        fontFamily = EditorFontFamily(rawValue: defaults.string(forKey: Keys.fontFamily) ?? "") ?? .system
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 15
        lineSpacing = defaults.object(forKey: Keys.lineSpacing) as? Double ?? 4.5
        maxContentWidth = defaults.object(forKey: Keys.maxWidth) as? Double ?? 720
        focusMode = defaults.object(forKey: Keys.focusMode) as? Bool ?? false
        spellChecking = defaults.object(forKey: Keys.spellChecking) as? Bool ?? false
        showWordCount = defaults.object(forKey: Keys.showWordCount) as? Bool ?? true
        sortField = SortField(rawValue: defaults.string(forKey: Keys.sortField) ?? "") ?? .modified
        sortAscending = defaults.object(forKey: Keys.sortAscending) as? Bool ?? false
        editorMode = EditorMode(rawValue: defaults.string(forKey: Keys.editorMode) ?? "") ?? .editor
        sidebarWidth = CGFloat(defaults.object(forKey: Keys.sidebarWidth) as? Double ?? 218)
        listWidth = CGFloat(defaults.object(forKey: Keys.listWidth) as? Double ?? 304)
        trashRetentionDays = defaults.object(forKey: Keys.trashRetention) as? Int ?? 30
    }

    // MARK: - Derived values

    var sortOrder: SortOrder {
        get { SortOrder(field: sortField, ascending: sortAscending) }
        set {
            sortField = newValue.field
            sortAscending = newValue.ascending
        }
    }

    /// The palette actually in use, honouring "follow system appearance".
    var theme: Theme {
        if followSystemAppearance {
            return ThemeCatalog.theme(id: systemIsDark ? ThemeCatalog.defaultDarkID : ThemeCatalog.defaultID)
        }
        return ThemeCatalog.theme(id: themeID)
    }

    var typography: EditorTypography {
        EditorTypography(
            family: fontFamily,
            size: CGFloat(fontSize),
            lineSpacing: CGFloat(lineSpacing),
            paragraphSpacing: CGFloat(lineSpacing * 1.9)
        )
    }

    /// CSS font fragment handed to the preview so both panes use the same typeface.
    var previewFontCSS: String {
        "font-family: \(fontFamily.cssFamily); font-size: \(Int(fontSize))px;"
    }

    var accentColor: NSColor { NSColor(hex: accentHex) }
    var accent: Color { Color(hex: accentHex) }

    func updateSystemAppearance(isDark: Bool) {
        if systemIsDark != isDark { systemIsDark = isDark }
    }
}
