import SwiftUI

// MARK: - Chrome constants

private enum SettingsChrome {
    static let panelWidth: CGFloat = 832
    static let panelHeight: CGFloat = 696
    static let sidebarWidth: CGFloat = 208
    /// Adaptive grid: ~3 columns at default width so theme cards are not squeezed.
    static let themeColumnMinimum: CGFloat = 172
    static let sidebarRowSpacing: CGFloat = 4
    static let sidebarHorizontalInset: CGFloat = 12
}

// MARK: - Panes

private enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance
    case shortcuts
    case updates

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .updates: "Updates"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintbrush.pointed.fill"
        case .shortcuts: "keyboard"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Sidebar row

private struct SettingsSidebarRowButton: View {
    let pane: SettingsPane
    @Binding var selectedPane: SettingsPane
    let t: AppTheme

    @State private var isHovered = false

    private var isSelected: Bool {
        selectedPane == pane
    }

    private var labelEmphasized: Bool {
        isSelected || isHovered
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPane = pane
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, alignment: .center)
                    .foregroundStyle(labelEmphasized ? t.text : t.textMuted)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(labelEmphasized ? t.text : t.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var rowBackground: Color {
        if isSelected {
            return t.selected
        }
        if isHovered {
            return t.hover
        }
        return .clear
    }
}

// MARK: - Root

struct SettingsView: View {
    @Environment(ThemeManager.self) var theme
    @EnvironmentObject private var appUpdater: AppUpdater
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPane: SettingsPane = .appearance

    private var t: AppTheme {
        theme.current
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            settingsSidebar
            Rectangle()
                .fill(t.border)
                .frame(width: 1)
            settingsDetail
        }
        .frame(width: SettingsChrome.panelWidth, height: SettingsChrome.panelHeight)
        .background(t.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Sidebar

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(t.accent.opacity(0.13))
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
                .frame(width: 34, height: 34)

                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.text)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsChrome.sidebarHorizontalInset + 2)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Rectangle()
                .fill(t.border.opacity(0.65))
                .frame(height: 1)
                .padding(.horizontal, SettingsChrome.sidebarHorizontalInset)

            VStack(spacing: SettingsChrome.sidebarRowSpacing) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarRowButton(
                        pane: pane,
                        selectedPane: $selectedPane,
                        t: t
                    )
                }
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsChrome.sidebarHorizontalInset)

            Spacer(minLength: 0)
        }
        .frame(width: SettingsChrome.sidebarWidth, height: SettingsChrome.panelHeight, alignment: .top)
        .background(t.sidebar)
    }

    // MARK: Detail

    private var settingsDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(selectedPane.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.textMuted)
                        .frame(width: 26, height: 26)
                        .background(t.hover.opacity(0.85))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(t.border)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch selectedPane {
                    case .appearance:
                        AppearanceSettingsDetail(theme: theme, t: t)
                    case .shortcuts:
                        ShortcutsSettingsPlaceholder(t: t)
                    case .updates:
                        UpdatesSettingsDetail(appUpdater: appUpdater, t: t)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(t.elevated)
    }
}

// MARK: - Shared inset card

private struct SettingsInsetCard<Content: View>: View {
    let t: AppTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(t.border.opacity(0.55), lineWidth: 1)
            )
    }
}

// MARK: - Appearance detail

private struct AppearanceSettingsDetail: View {
    @Bindable var theme: ThemeManager
    let t: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a theme for the application chrome.")
                .font(.system(size: 13))
                .foregroundStyle(t.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 16)

            Rectangle()
                .fill(t.border)
                .frame(height: 1)
                .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 0) {
                terminalOverrideRow
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Rectangle()
                .fill(t.border)
                .frame(height: 1)
                .padding(.horizontal, 22)

            Text("Themes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.textFaint)
                .tracking(0.5)
                .textCase(.uppercase)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 10)

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: SettingsChrome.themeColumnMinimum),
                        spacing: 14,
                        alignment: .top
                    ),
                ],
                alignment: .leading,
                spacing: 18
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
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        }
    }

    private var terminalOverrideRow: some View {
        SettingsInsetCard(t: t) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Override terminal colors")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(
                        "Applies background, text, cursor, and ANSI palette to match the selected theme. Font, keybindings, and all other Ghostty settings are preserved."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(t.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $theme.overridesTerminalColors)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(t.accent)
            }
        }
    }
}

// MARK: - Updates

private struct UpdatesPreferenceToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let t: AppTheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(t.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(t.accent)
                .padding(.top, 1)
        }
    }
}

private struct UpdatesSettingsDetail: View {
    @ObservedObject var appUpdater: AppUpdater
    let t: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appUpdater.isSparkleConfigured {
                updatesSparkleBody
            } else {
                updatesUnavailableBody
            }
        }
    }

    private var updatesSparkleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(t.accent.opacity(0.14))
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Software updates")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.textFaint)
                        .tracking(0.45)
                        .textCase(.uppercase)
                    Text(
                        "Choose how often Termscape checks for a newer version online, and whether to fetch installers before you install."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(t.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Rectangle()
                .fill(t.border)
                .frame(height: 1)
                .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 12) {
                SettingsInsetCard(t: t) {
                    UpdatesPreferenceToggleRow(
                        title: "Automatically check for updates",
                        subtitle:
                        "On a schedule, Termscape contacts the update server to see if a newer build is available. You can still run a manual check any time using the button below.",
                        isOn: appUpdater.automaticallyChecksForUpdatesBinding,
                        t: t
                    )
                }

                SettingsInsetCard(t: t) {
                    VStack(alignment: .leading, spacing: 0) {
                        UpdatesPreferenceToggleRow(
                            title: "Automatically download updates",
                            subtitle:
                            "When a new version is found, download the update package in the background so it is ready when you choose to install. Relaunching or replacing the app always waits for your confirmation.",
                            isOn: appUpdater.automaticallyDownloadsUpdatesBinding,
                            t: t
                        )
                        .opacity(appUpdater.automaticallyChecksForUpdates ? 1 : 0.5)
                        .disabled(!appUpdater.automaticallyChecksForUpdates)

                        if !appUpdater.automaticallyChecksForUpdates {
                            Text("Background downloads require automatic update checks to be on.")
                                .font(.system(size: 11))
                                .foregroundStyle(t.textFaint)
                                .padding(.top, 10)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            SettingsInsetCard(t: t) {
                HStack(alignment: .center, spacing: 16) {
                    Button("Check for Updates…") {
                        appUpdater.checkForUpdates()
                    }
                    .disabled(!appUpdater.canCheckForUpdates)
                    .buttonStyle(TermscapePrimaryButtonStyle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last check")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(t.textFaint)
                            .tracking(0.35)
                            .textCase(.uppercase)
                        if let last = appUpdater.lastUpdateCheckDate {
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(t.textMuted)
                        } else {
                            Text("Not yet")
                                .font(.system(size: 12))
                                .foregroundStyle(t.textFaint)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    private var updatesUnavailableBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates are not available in this build.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(t.text)
            Text(
                "The app is missing update feed configuration (for example in local debug builds). Release builds can enable Sparkle from the bundle so checks appear here."
            )
            .font(.system(size: 13))
            .foregroundStyle(t.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }
}

// MARK: - Shortcuts placeholder

private struct ShortcutsSettingsPlaceholder: View {
    let t: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard shortcuts for Termscape are not configurable yet. This section will host shortcut editing once the behavior surface is defined.")
                .font(.system(size: 13))
                .foregroundStyle(t.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            SettingsInsetCard(t: t) {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 22))
                        .foregroundStyle(t.textFaint)
                    Text("Coming later")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(t.textMuted)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
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
                miniPreview
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? themeOption.accent : Color.clear,
                                lineWidth: 2
                            )
                    )

                HStack(spacing: 7) {
                    Text(themeOption.emoji)
                        .font(.system(size: 12))
                    Text(themeOption.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? currentTheme.text : currentTheme.textMuted)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(themeOption.accent)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var miniPreview: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(themeOption.textFaint)
                            .frame(width: 8, height: 3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.top, 8)

                ForEach(0 ..< 3, id: \.self) { i in
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
            .frame(width: 62)
            .background(themeOption.sidebar)

            Rectangle()
                .fill(themeOption.border)
                .frame(width: 1)

            VStack(spacing: 0) {
                HStack(spacing: 4) {
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

                themeOption.canvasBackground.color
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
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
        .frame(height: 96)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? themeOption.accent.opacity(0.35) : currentTheme.border.opacity(0.65),
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
    var color: Color {
        Color(self)
    }
}
