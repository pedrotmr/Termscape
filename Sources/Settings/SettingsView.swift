import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) var theme
    @Environment(\.dismiss) private var dismiss

    private var t: AppTheme { theme.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("Choose a theme for the application chrome")
                        .font(.system(size: 12))
                        .foregroundStyle(t.textMuted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.textMuted)
                        .frame(width: 22, height: 22)
                        .background(t.hover)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .overlay(t.border)

            // Terminal color override toggle
            terminalOverrideRow

            Divider()
                .overlay(t.border)

            // Theme grid — scrollable to handle many themes
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 16
                ) {
                    ForEach(AppTheme.all) { themeOption in
                        ThemeCard(
                            themeOption: themeOption,
                            isSelected: theme.current.id == themeOption.id,
                            currentTheme: t
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                theme.current = themeOption
                            }
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxHeight: 480)
        }
        .frame(width: 620)
        .background(t.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Terminal override row

    @ViewBuilder
    private var terminalOverrideRow: some View {
        @Bindable var theme = theme
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Override terminal colors")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.text)
                Text("Applies background, text, cursor, and ANSI palette to match the selected theme. Font, keybindings, and all other Ghostty settings are preserved.")
                    .font(.system(size: 11))
                    .foregroundStyle(t.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $theme.overridesTerminalColors)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(t.accent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Theme card

private struct ThemeCard: View {
    let themeOption: AppTheme
    let isSelected: Bool
    let currentTheme: AppTheme
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // Mini app preview
                miniPreview
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                isSelected ? themeOption.accent : Color.clear,
                                lineWidth: 1.5
                            )
                    )

                // Name row
                HStack(spacing: 6) {
                    Text(themeOption.emoji)
                        .font(.system(size: 11))
                    Text(themeOption.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? currentTheme.text : currentTheme.textMuted)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(themeOption.accent)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: Mini app preview

    private var miniPreview: some View {
        HStack(spacing: 0) {
            // Sidebar strip
            VStack(spacing: 6) {
                // Group header dots
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(themeOption.textFaint)
                            .frame(width: 8, height: 3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.top, 8)

                // Workspace rows
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(dotColors[i % dotColors.count])
                            .frame(width: 4, height: 4)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(i == 0 ? themeOption.textMuted : themeOption.textFaint)
                            .frame(height: 3)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(i == 0 ? themeOption.selected : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.horizontal, 4)
                }

                Spacer()
            }
            .frame(width: 60)
            .background(themeOption.sidebar)

            // Vertical divider
            Rectangle()
                .fill(themeOption.border)
                .frame(width: 1)

            // Main area
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 4) {
                    // Active tab pill
                    HStack(spacing: 3) {
                        Image(systemName: "terminal")
                            .font(.system(size: 5))
                            .foregroundStyle(themeOption.textMuted)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(themeOption.textMuted)
                            .frame(width: 18, height: 3)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .background(themeOption.selected)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(themeOption.accent)
                            .frame(height: 1.5)
                            .padding(.horizontal, 4)
                    }

                    Spacer()
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(themeOption.surface)

                Rectangle()
                    .fill(themeOption.border)
                    .frame(height: 0.5)

                // Terminal canvas
                themeOption.canvasBackground.color
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        // Faux terminal lines
                        VStack(alignment: .leading, spacing: 3) {
                            terminalLine(width: 0.6, color: themeOption.accent)
                            terminalLine(width: 0.45, color: themeOption.textMuted)
                            terminalLine(width: 0.7, color: themeOption.textFaint)
                            terminalLine(width: 0.3, color: themeOption.textFaint)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
            }
        }
        .frame(height: 90)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    isSelected ? themeOption.accent.opacity(0.4) : currentTheme.border,
                    lineWidth: 1
                )
        )
    }

    private func terminalLine(width: CGFloat, color: Color) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: geo.size.width * width, height: 2.5)
        }
        .frame(height: 2.5)
    }

    private let dotColors: [Color] = [
        Color(red: 0.40, green: 0.60, blue: 1.00),
        Color(red: 0.35, green: 0.85, blue: 0.60),
        Color(red: 1.00, green: 0.55, blue: 0.35),
    ]
}

// MARK: - NSColor → Color helper

extension NSColor {
    var color: Color { Color(self) }
}
