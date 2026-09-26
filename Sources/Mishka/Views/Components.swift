import SwiftUI

/// A small count badge shown at the trailing edge of sidebar rows.
struct CountBadge: View {
    let count: Int
    let theme: Theme
    var highlighted: Bool = false

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Color.white.opacity(0.9) : Color(hex: theme.tertiaryText))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(highlighted ? Color.white.opacity(0.18) : Color(hex: theme.text).opacity(0.06))
                )
        }
    }
}

/// Sidebar row: icon, title, count, with a Bear-like rounded selection.
struct SidebarRow: View {
    let title: String
    let symbol: String
    var count: Int = 0
    let isSelected: Bool
    let theme: Theme
    let accent: Color
    var indent: CGFloat = 0
    var hasChildren: Bool = false
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            if indent > 0 { Spacer().frame(width: indent) }

            if hasChildren {
                Button {
                    onToggleExpand?()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(hex: theme.tertiaryText))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if indent > 0 {
                Spacer().frame(width: 10)
            }

            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? accent : Color(hex: theme.secondaryText))
                .frame(width: 15)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color(hex: theme.text))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            CountBadge(count: count, theme: theme, highlighted: isSelected)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var background: Color {
        if isSelected { return accent.opacity(theme.isDark ? 0.26 : 0.16) }
        if isHovering { return Color(hex: theme.text).opacity(0.05) }
        return .clear
    }
}

/// Section caption used above groups of sidebar rows.
struct SidebarSectionHeader: View {
    let title: String
    let theme: Theme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Color(hex: theme.tertiaryText))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }
}

/// Borderless icon button used in toolbars and list headers.
struct IconButton: View {
    let symbol: String
    let theme: Theme
    var help: String = ""
    var isActive: Bool = false
    var accent: Color = .accentColor
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isActive ? accent : Color(hex: theme.secondaryText))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color(hex: theme.text).opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// Bear-style tag chip used in the note list rows.
struct TagChip: View {
    let tag: String
    let theme: Theme
    let accent: Color

    var body: some View {
        Text("#" + tag)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(accent.opacity(0.92))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(theme.isDark ? 0.18 : 0.11))
            )
    }
}

/// Search field styled to match the note list column.
struct SearchField: View {
    @Binding var text: String
    let theme: Theme
    let accent: Color
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color(hex: theme.tertiaryText))

            TextField("Search notes", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(hex: theme.text))
                .focused(isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: theme.tertiaryText))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(hex: theme.text).opacity(theme.isDark ? 0.09 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? accent.opacity(0.65) : .clear, lineWidth: 1.2)
        )
    }
}

/// Slightly translucent vertical separator matching the theme.
struct ThemedDivider: View {
    let theme: Theme
    var body: some View {
        Rectangle()
            .fill(Color(hex: theme.border).opacity(0.85))
            .frame(width: 1)
    }
}

/// Empty-state placeholder used in the editor and note list.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let subtitle: String
    let theme: Theme
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(accent.opacity(0.55))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: theme.secondaryText))
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(hex: theme.tertiaryText))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
