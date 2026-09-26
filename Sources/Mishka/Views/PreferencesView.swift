import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            TypographySettingsView()
                .tabItem { Label("Typography", systemImage: "textformat") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 580, height: 480)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    private var theme: Theme { settings.theme }

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Follow system appearance", isOn: $settings.followSystemAppearance)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("When on, Mishka switches between the default light and dark themes with macOS.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent colour")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 8) {
                        ForEach(AccentCatalog.all) { accent in
                            Circle()
                                .fill(Color(hex: accent.hex))
                                .frame(width: 21, height: 21)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: settings.accentHex == accent.hex ? 2 : 0)
                                        .padding(-2.5)
                                )
                                .help(accent.name)
                                .onTapGesture { settings.accentHex = accent.hex }
                        }
                    }
                }

                themeSection("Light", themes: ThemeCatalog.lightThemes, columns: columns)
                themeSection("Dark", themes: ThemeCatalog.darkThemes, columns: columns)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(settings.followSystemAppearance ? 0.55 : 1)
        .allowsHitTesting(!settings.followSystemAppearance)
        .overlay(alignment: .top) {
            if settings.followSystemAppearance {
                Text("Turn off “Follow system appearance” to pick a theme")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.thinMaterial))
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func themeSection(_ title: String, themes: [Theme], columns: [GridItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(themes) { candidate in
                    ThemeCard(
                        theme: candidate,
                        accent: settings.accent,
                        isSelected: settings.themeID == candidate.id
                    )
                    .onTapGesture { settings.themeID = candidate.id }
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let accent: Color
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hex: theme.background))
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color(hex: theme.heading)).frame(width: 44, height: 5)
                    Capsule().fill(Color(hex: theme.text).opacity(0.55)).frame(width: 68, height: 3.5)
                    Capsule().fill(Color(hex: theme.text).opacity(0.34)).frame(width: 54, height: 3.5)
                    Capsule().fill(Color(hex: theme.tag)).frame(width: 30, height: 3.5)
                }
                .padding(9)
            }
            .frame(height: 56)

            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(theme.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(hex: theme.text))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(hex: theme.sidebar))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
    }
}

// MARK: - Typography

private struct TypographySettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Typeface")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 8) {
                        ForEach(EditorFontFamily.allCases) { family in
                            Button {
                                settings.fontFamily = family
                            } label: {
                                Text(family.label)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(settings.fontFamily == family ? settings.accent.opacity(0.18) : Color.primary.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(settings.fontFamily == family ? settings.accent : .clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                slider("Text size", value: $settings.fontSize, range: 12...22, step: 0.5, suffix: "pt")
                slider("Line spacing", value: $settings.lineSpacing, range: 0...12, step: 0.5, suffix: "pt")
                slider("Column width", value: $settings.maxContentWidth, range: 480...1100, step: 20, suffix: "px")

                Divider()

                Text("Preview")
                    .font(.system(size: 12, weight: .semibold))
                Text("# Mishka\n\n**Bold**, *italic* and `code` in the typeface you picked.")
                    .font(Font(settings.typography.baseFont()))
                    .lineSpacing(CGFloat(settings.lineSpacing))
                    .foregroundStyle(Color(hex: settings.theme.text))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: settings.theme.background))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(value.wrappedValue, specifier: step < 1 ? "%.1f" : "%.0f")\(suffix)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

// MARK: - Editor

private struct EditorSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Focused mode", isOn: $settings.focusMode)
                    .toggleStyle(.switch)
                caption("Dim every paragraph except the one you are writing in.")

                Toggle("Check spelling while typing", isOn: $settings.spellChecking)
                    .toggleStyle(.switch)

                Toggle("Show the status bar", isOn: $settings.showWordCount)
                    .toggleStyle(.switch)
                caption("Word count, character count and reading time below the editor.")

                Divider()

                Picker("Default view", selection: $settings.editorMode) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Divider()

                HStack {
                    Text("Keep deleted notes for")
                        .font(.system(size: 12))
                    Picker("", selection: $settings.trashRetentionDays) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("Forever").tag(0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                caption("Trash is emptied automatically on launch when notes are older than this.")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes folder")
                        .font(.system(size: 12, weight: .semibold))
                    Text(state.store.rootURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    HStack(spacing: 8) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([state.store.rootURL])
                        }
                        Button("Reload from Disk") {
                            state.store.reloadFromDisk()
                            state.status("Reloaded from disk")
                        }
                    }
                }

                Text("Every note is a plain `.md` file. Metadata lives in `library.json` beside them and is rebuilt automatically if it goes missing — your text is never locked in.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 10) {
                    Text("\(state.store.activeNotes.count) notes")
                    Text("·")
                    Text("\(state.store.flatTagCounts.count) tags")
                    Text("·")
                    Text("\(state.store.trashedNotes.count) in trash")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Text("Trash")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Empty Trash") {
                        state.store.emptyTrash()
                        state.status("Trash emptied")
                    }
                    .disabled(state.store.trashedNotes.isEmpty)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
