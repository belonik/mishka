import Foundation

// MARK: - Accent

/// A single user-selectable accent colour.
///
/// `id` and `hex` are intentionally the same value: the hex string is a stable,
/// serialisable identity that survives theme switches and is stored in preferences.
struct Accent: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: String

    init(id: String, name: String, hex: String) {
        self.id = id
        self.name = name
        self.hex = hex
    }

    /// Convenience: the hex string doubles as the identifier.
    init(hex: String, name: String) {
        self.init(id: hex, name: name, hex: hex)
    }
}

// MARK: - Accent catalog

/// The twelve Bear-like accents offered in Settings › Appearance.
enum AccentCatalog {
    /// Red is deliberately first: it is the historical Mishka accent.
    static let all: [Accent] = [
        Accent(hex: "#E8452B", name: "Red"),
        Accent(hex: "#E8872B", name: "Orange"),
        Accent(hex: "#D9A400", name: "Yellow"),
        Accent(hex: "#3FA45B", name: "Green"),
        Accent(hex: "#2AA69A", name: "Mint"),
        Accent(hex: "#1F8A9E", name: "Teal"),
        Accent(hex: "#2D7FF9", name: "Blue"),
        Accent(hex: "#5157D6", name: "Indigo"),
        Accent(hex: "#8A5CF6", name: "Purple"),
        Accent(hex: "#E0559B", name: "Pink"),
        Accent(hex: "#9A6A4A", name: "Brown"),
        Accent(hex: "#6B7280", name: "Graphite"),
    ]

    /// The accent shown first in the picker and used by the default themes.
    static var `default`: Accent { all[0] }

    /// Looks up an accent by hex string. Unknown or malformed values fall back to
    /// the first entry so callers never have to deal with an optional.
    static func accent(hex: String) -> Accent {
        let normalised = normalise(hex)
        return all.first { normalise($0.hex) == normalised } ?? all[0]
    }

    /// Uppercases a hex string and guarantees a leading `#` so that `#e8452b`
    /// and `E8452B` resolve to the same accent.
    private static func normalise(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
    }
}

// MARK: - Theme catalog

/// Every bundled theme.
///
/// Palettes are grouped into light and dark families and each one is built from a
/// single base surface that `sidebar`, `list`, `elevated`, `border` and
/// `codeBackground` shift by only a few percent, so the three-column layout reads
/// as one continuous surface. `selection` is a solid colour that approximates the
/// blend of the accent over the background at roughly 22 % alpha, which keeps the
/// primary text readable while the highlight is still clearly visible.
enum ThemeCatalog {

    // MARK: Defaults

    /// The default light theme: warm paper with the classic Mishka red.
    static let defaultID: String = "mishka-light"

    /// The default dark theme: Bear's charcoal.
    static let defaultDarkID: String = "mishka-dark"

    // MARK: All themes

    static let all: [Theme] = [
        mishkaLight,
        mishkaDark,
        charcoal,
        graphite,
        sepia,
        solarizedLight,
        solarizedDark,
        dracula,
        nord,
        ayuMirage,
        rosePine,
        cobalt,
        everforest,
        toothpaste,
        highContrast,
        ocean,
    ]

    // MARK: Lookup

    /// The theme with the given id, or the default light theme when it is unknown.
    ///
    /// The fallback is looked up by index rather than by recursing into this
    /// function, so an unknown id can never loop.
    static func theme(id: String) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }

    static var lightThemes: [Theme] { all.filter { !$0.isDark } }
    static var darkThemes: [Theme] { all.filter { $0.isDark } }

    // MARK: - Light themes

    private static let mishkaLight = Theme(
        id: "mishka-light",
        name: "Mishka Light",
        isDark: false,
        background: "#FDFDFB",
        sidebar: "#F8F8F4",
        list: "#FAFAF7",
        elevated: "#FFFFFF",
        text: "#1C1C1E",
        secondaryText: "#565660",
        tertiaryText: "#8A8A93",
        heading: "#0F0F11",
        link: "#C33A22",
        tag: "#B03520",
        quote: "#5A5A63",
        codeText: "#A8250F",
        codeBackground: "#F1F1EC",
        selection: "#F6D9D3",
        border: "#E6E6DF",
        marker: "#91919B"
    )

    private static let graphite = Theme(
        id: "graphite",
        name: "Graphite",
        isDark: false,
        background: "#F5F7FA",
        sidebar: "#E9EDF3",
        list: "#EFF3F8",
        elevated: "#FFFFFF",
        text: "#242A33",
        secondaryText: "#4C5566",
        tertiaryText: "#767F91",
        heading: "#161A21",
        link: "#1D5FB0",
        tag: "#1A5499",
        quote: "#4C5566",
        codeText: "#134A85",
        codeBackground: "#E2E8F0",
        selection: "#CCDAEC",
        border: "#D5DCE6",
        marker: "#848EA3"
    )

    private static let sepia = Theme(
        id: "sepia",
        name: "Sepia",
        isDark: false,
        background: "#F6EFE0",
        sidebar: "#EDE3CD",
        list: "#F2EAD8",
        elevated: "#FBF6EA",
        text: "#43382C",
        secondaryText: "#6B5B47",
        tertiaryText: "#93826A",
        heading: "#2E251B",
        link: "#8F4A1E",
        tag: "#7E4119",
        quote: "#5E5040",
        codeText: "#7A3F16",
        codeBackground: "#E9DEC6",
        selection: "#E5D2AF",
        border: "#DCCFB4",
        marker: "#98866E"
    )

    private static let solarizedLight = Theme(
        id: "solarized-light",
        name: "Solarized Light",
        isDark: false,
        background: "#FDF6E3",
        sidebar: "#EEE8D5",
        list: "#F5EEDB",
        elevated: "#FFFBF0",
        text: "#52666E",
        secondaryText: "#4F6369",
        tertiaryText: "#7A9098",
        heading: "#42565D",
        link: "#196395",
        tag: "#175A88",
        quote: "#4F6369",
        codeText: "#8E5C0F",
        codeBackground: "#EEE8D5",
        selection: "#D8E1DB",
        border: "#E3DCC7",
        marker: "#7C8D8D"
    )

    private static let toothpaste = Theme(
        id: "toothpaste",
        name: "Toothpaste",
        isDark: false,
        background: "#FFFFFF",
        sidebar: "#F0F6F8",
        list: "#F7FBFC",
        elevated: "#FFFFFF",
        text: "#2E3440",
        secondaryText: "#546070",
        tertiaryText: "#7C8798",
        heading: "#1B2029",
        link: "#00768C",
        tag: "#00687C",
        quote: "#4A5666",
        codeText: "#00707F",
        codeBackground: "#EAF2F5",
        selection: "#CDE9EE",
        border: "#DCE6EA",
        marker: "#8894A7"
    )

    private static let highContrast = Theme(
        id: "high-contrast",
        name: "High Contrast",
        isDark: false,
        background: "#FFFFFF",
        sidebar: "#F0F0F0",
        list: "#F7F7F7",
        elevated: "#FFFFFF",
        text: "#000000",
        secondaryText: "#3D3D3D",
        tertiaryText: "#6B6B6B",
        heading: "#000000",
        link: "#0043A8",
        tag: "#0043A8",
        quote: "#1F1F1F",
        codeText: "#1F1F1F",
        codeBackground: "#EDEDED",
        selection: "#CCDDF5",
        border: "#BDBDBD",
        marker: "#767676"
    )

    // MARK: - Dark themes

    private static let mishkaDark = Theme(
        id: "mishka-dark",
        name: "Mishka Dark",
        isDark: true,
        background: "#1E2024",
        sidebar: "#181A1D",
        list: "#1B1D21",
        elevated: "#26292E",
        text: "#E6E6E6",
        secondaryText: "#ABABAB",
        tertiaryText: "#787A80",
        heading: "#FFFFFF",
        link: "#FF6B4F",
        tag: "#FF7D63",
        quote: "#C8C8C8",
        codeText: "#FF9E85",
        codeBackground: "#26292E",
        selection: "#4C3833",
        border: "#33363B",
        marker: "#6E7178"
    )

    private static let charcoal = Theme(
        id: "charcoal",
        name: "Charcoal",
        isDark: true,
        background: "#1C1C1E",
        sidebar: "#161618",
        list: "#191919",
        elevated: "#272729",
        text: "#E4E4E4",
        secondaryText: "#ACACAC",
        tertiaryText: "#7B7B7B",
        heading: "#FAFAFA",
        link: "#C9C9C9",
        tag: "#BDBDBD",
        quote: "#B8B8B8",
        codeText: "#E4E4E4",
        codeBackground: "#272729",
        selection: "#3A3A3D",
        border: "#313134",
        marker: "#707072"
    )

    private static let solarizedDark = Theme(
        id: "solarized-dark",
        name: "Solarized Dark",
        isDark: true,
        background: "#002B36",
        sidebar: "#00212B",
        list: "#002630",
        elevated: "#073642",
        text: "#93A1A1",
        secondaryText: "#839496",
        tertiaryText: "#6D7B80",
        heading: "#EEE8D5",
        link: "#2AA1E8",
        tag: "#4FB3EC",
        quote: "#9DAFAF",
        codeText: "#E8875A",
        codeBackground: "#073642",
        selection: "#06384C",
        border: "#0B3D49",
        marker: "#62747A"
    )

    private static let dracula = Theme(
        id: "dracula",
        name: "Dracula",
        isDark: true,
        background: "#282A36",
        sidebar: "#20222C",
        list: "#242631",
        elevated: "#343746",
        text: "#F8F8F2",
        secondaryText: "#C8CAD8",
        tertiaryText: "#9497AB",
        heading: "#FFFFFF",
        link: "#BD93F9",
        tag: "#D6ACFF",
        quote: "#C3C6D6",
        codeText: "#F1FA8C",
        codeBackground: "#343746",
        selection: "#474A5C",
        border: "#3C3F51",
        marker: "#7B7F94"
    )

    private static let nord = Theme(
        id: "nord",
        name: "Nord",
        isDark: true,
        background: "#2E3440",
        sidebar: "#272C36",
        list: "#2B313C",
        elevated: "#3B4252",
        text: "#ECEFF4",
        secondaryText: "#C2CAD8",
        tertiaryText: "#8E99AC",
        heading: "#FFFFFF",
        link: "#88C0D0",
        tag: "#9ACBDA",
        quote: "#B8C2D2",
        codeText: "#A3BE8C",
        codeBackground: "#3B4252",
        selection: "#3E4A5C",
        border: "#434C5E",
        marker: "#7A8496"
    )

    private static let ayuMirage = Theme(
        id: "ayu-mirage",
        name: "Ayu Mirage",
        isDark: true,
        background: "#1F2430",
        sidebar: "#191E28",
        list: "#1C212B",
        elevated: "#242936",
        text: "#CBCCC6",
        secondaryText: "#A3A6A8",
        tertiaryText: "#85878A",
        heading: "#F2F3EE",
        link: "#E0A32E",
        tag: "#E8B44F",
        quote: "#B5B7B2",
        codeText: "#F29E74",
        codeBackground: "#242936",
        selection: "#3A3F4C",
        border: "#2F3543",
        marker: "#6E7484"
    )

    private static let rosePine = Theme(
        id: "rose-pine",
        name: "Rosé Pine",
        isDark: true,
        background: "#191724",
        sidebar: "#13111C",
        list: "#16141F",
        elevated: "#1F1D2E",
        text: "#E0DEF4",
        secondaryText: "#C0BDD8",
        tertiaryText: "#8E8AA8",
        heading: "#F4F2FF",
        link: "#EBBCBA",
        tag: "#F0CECB",
        quote: "#C8C5DE",
        codeText: "#9CCFD8",
        codeBackground: "#1F1D2E",
        selection: "#3B3550",
        border: "#302D40",
        marker: "#79748F"
    )

    private static let cobalt = Theme(
        id: "cobalt",
        name: "Cobalt",
        isDark: true,
        background: "#193549",
        sidebar: "#122A3C",
        list: "#162F42",
        elevated: "#1F3E56",
        text: "#E1EFFE",
        secondaryText: "#AFC7DE",
        tertiaryText: "#8399B1",
        heading: "#FFFFFF",
        link: "#FFC600",
        tag: "#FFD34D",
        quote: "#C4D8EC",
        codeText: "#7FDBCA",
        codeBackground: "#1F3E56",
        selection: "#3C4A60",
        border: "#28455E",
        marker: "#7C93AC"
    )

    private static let everforest = Theme(
        id: "everforest",
        name: "Everforest",
        isDark: true,
        background: "#2D353B",
        sidebar: "#262E33",
        list: "#2A3238",
        elevated: "#343F44",
        text: "#D3C6AA",
        secondaryText: "#B3A78E",
        tertiaryText: "#8E8B71",
        heading: "#EFEBD4",
        link: "#A7C080",
        tag: "#B9CF93",
        quote: "#BFB49A",
        codeText: "#E69875",
        codeBackground: "#343F44",
        selection: "#42514A",
        border: "#3B464B",
        marker: "#78816C"
    )

    private static let ocean = Theme(
        id: "ocean",
        name: "Ocean",
        isDark: true,
        background: "#0F1B2D",
        sidebar: "#0A1422",
        list: "#0D1827",
        elevated: "#16263D",
        text: "#DCE6F2",
        secondaryText: "#A9BBD1",
        tertiaryText: "#7A8CA3",
        heading: "#F4F8FD",
        link: "#4D9FE0",
        tag: "#6BB2EA",
        quote: "#B6C6DA",
        codeText: "#5FC9A8",
        codeBackground: "#16263D",
        selection: "#2A4666",
        border: "#1D3252",
        marker: "#6B7E95"
    )
}
