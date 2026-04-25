import AppKit
import SwiftUI

// Ported workbench + terminal colors from Cursor.app bundled extensions (`theme-cursor`, `theme-defaults`, `theme-*`).

extension AppTheme {
    // MARK: - Cursor

    static let cursorLight = AppTheme(
        id: "cursor-light",
        name: "Cursor Light",
        emoji: "☀️",
        isDark: false,
        sidebar: Color(red: 0.953, green: 0.953, blue: 0.953), // #F3F3F3
        surface: Color(red: 0.988, green: 0.988, blue: 0.988), // #FCFCFC
        elevated: Color(red: 0.929, green: 0.929, blue: 0.929), // #EDEDED
        accent: Color(red: 0.125, green: 0.396, blue: 0.584), // #206595
        border: Color.black.opacity(0.08),
        text: Color(red: 0.078, green: 0.078, blue: 0.078), // #141414
        textMuted: Color(red: 0.078, green: 0.078, blue: 0.078).opacity(0.62),
        textFaint: Color(red: 0.078, green: 0.078, blue: 0.078).opacity(0.42),
        hover: Color.black.opacity(0.045),
        selected: Color.black.opacity(0.085),
        canvasBackground: NSColor(red: 0.988, green: 0.988, blue: 0.988, alpha: 1),
        accentNSColor: NSColor(red: 0.125, green: 0.396, blue: 0.584, alpha: 0.85),
        terminalTheme: TerminalTheme(
            background: "#F3F3F3",
            foreground: "#141414",
            cursor: "#141414",
            selectionBackground: "#D0D0D0",
            selectionForeground: "#141414",
            palette: [
                "#2A2A2A", "#CF2D56", "#1F8A65", "#A16900",
                "#3C7CAB", "#B8448B", "#4C7F8C", "#FCFCFC",
                "#5A5A5A", "#E75E78", "#55A583", "#C08532",
                "#6299C3", "#D06BA6", "#6F9BA6", "#FFFFFF",
            ]
        )
    )

    // MARK: - VS Code defaults (`theme-defaults`)

    /// Integrated terminal palette when a theme JSON omits `terminal.ansi*`.
    private static let vscodeDarkIntegratedPalette: [String] = [
        "#1E1E1E", "#F14C4C", "#23D18B", "#F5F543", "#3B8EEA", "#BC3FBC", "#29B8DB", "#CCCCCC",
        "#656565", "#F14C4C", "#23D18B", "#F5F543", "#3B8EEA", "#BC3FBC", "#29B8DB", "#FFFFFF",
    ]

    static let vscodeDarkModern = AppTheme(
        id: "vscode-dark-modern",
        name: "Dark Modern",
        emoji: "🪟",
        isDark: true,
        sidebar: Color(red: 0.094, green: 0.094, blue: 0.094), // #181818
        surface: Color(red: 0.122, green: 0.122, blue: 0.122), // #1F1F1F
        elevated: Color(red: 0.192, green: 0.192, blue: 0.192), // #313131
        accent: Color(red: 0.0, green: 0.471, blue: 0.831), // #0078D4
        border: Color.white.opacity(0.09),
        text: Color.white,
        textMuted: Color(white: 0.80),
        textFaint: Color(white: 0.55),
        hover: Color.white.opacity(0.06),
        selected: Color.white.opacity(0.11),
        canvasBackground: NSColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1),
        accentNSColor: NSColor(red: 0.0, green: 0.471, blue: 0.831, alpha: 0.88),
        terminalTheme: TerminalTheme(
            background: "#1F1F1F",
            foreground: "#CCCCCC",
            cursor: "#0078D4",
            selectionBackground: "#264F78",
            selectionForeground: "#CCCCCC",
            palette: vscodeDarkIntegratedPalette
        )
    )

    static let vscodeDarkVS = AppTheme(
        id: "vscode-dark-vs",
        name: "VS Code Dark",
        emoji: "🔷",
        isDark: true,
        sidebar: Color(red: 0.145, green: 0.145, blue: 0.149),
        surface: Color(red: 0.118, green: 0.118, blue: 0.118),
        elevated: Color(red: 0.176, green: 0.176, blue: 0.180),
        accent: Color(red: 0.0, green: 0.478, blue: 0.800),
        border: Color.white.opacity(0.08),
        text: Color(red: 0.831, green: 0.831, blue: 0.831),
        textMuted: Color(white: 0.55),
        textFaint: Color(white: 0.38),
        hover: Color.white.opacity(0.055),
        selected: Color.white.opacity(0.10),
        canvasBackground: NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1),
        accentNSColor: NSColor(red: 0.0, green: 0.478, blue: 0.800, alpha: 0.88),
        terminalTheme: TerminalTheme(
            background: "#1E1E1E",
            foreground: "#D4D4D4",
            cursor: "#FFFFFF",
            selectionBackground: "#3A3D41",
            selectionForeground: "#D4D4D4",
            palette: vscodeDarkIntegratedPalette
        )
    )

    // MARK: - Other bundled color themes

    static let abyss = AppTheme(
        id: "abyss",
        name: "Abyss",
        emoji: "🌊",
        isDark: true,
        sidebar: Color(red: 0.024, green: 0.024, blue: 0.129), // #060621
        surface: Color(red: 0.0, green: 0.047, blue: 0.094), // #000c18
        elevated: Color(red: 0.031, green: 0.125, blue: 0.314), // #082050
        accent: Color(red: 0.733, green: 0.855, blue: 1.0), // #bbdaff
        border: Color(red: 0.467, green: 0.855, blue: 1.0).opacity(0.22),
        text: Color(red: 0.8, green: 0.875, blue: 1.0),
        textMuted: Color.white.opacity(0.55),
        textFaint: Color.white.opacity(0.35),
        hover: Color.white.opacity(0.06),
        selected: Color.white.opacity(0.12),
        canvasBackground: NSColor(red: 0.0, green: 0.047, blue: 0.094, alpha: 1),
        accentNSColor: NSColor(red: 0.733, green: 0.855, blue: 1.0, alpha: 0.88),
        terminalTheme: TerminalTheme(
            background: "#000c18",
            foreground: "#f8f8f8",
            cursor: "#bbdaff",
            selectionBackground: "#770811",
            selectionForeground: "#f8f8f8",
            palette: [
                "#111111", "#ff9da4", "#d1f1a9", "#ffeead",
                "#bbdaff", "#ebbbff", "#99ffff", "#cccccc",
                "#333333", "#ff7882", "#b8f171", "#ffe580",
                "#80baff", "#d778ff", "#78ffff", "#ffffff",
            ]
        )
    )

    static let solarizedDark = AppTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        emoji: "☀️",
        isDark: true,
        sidebar: Color(red: 0.0, green: 0.129, blue: 0.169), // #00212B
        surface: Color(red: 0.0, green: 0.169, blue: 0.212), // #002B36
        elevated: Color(red: 0.027, green: 0.212, blue: 0.259), // #073642
        accent: Color(red: 0.149, green: 0.545, blue: 0.824), // #268bd2
        border: Color(red: 0.396, green: 0.482, blue: 0.514).opacity(0.35), // base0
        text: Color(red: 0.839, green: 0.859, blue: 0.859), // #d6dbdb
        textMuted: Color(red: 0.514, green: 0.580, blue: 0.588).opacity(0.95), // #586e75
        textFaint: Color(red: 0.514, green: 0.580, blue: 0.588).opacity(0.65),
        hover: Color.white.opacity(0.05),
        selected: Color.white.opacity(0.09),
        canvasBackground: NSColor(red: 0.0, green: 0.169, blue: 0.212, alpha: 1),
        accentNSColor: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 0.88),
        terminalTheme: TerminalTheme(
            background: "#002b36",
            foreground: "#839496",
            cursor: "#93a1a1",
            selectionBackground: "#073642",
            selectionForeground: "#93a1a1",
            palette: [
                "#073642", "#dc322f", "#859900", "#b58900",
                "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83",
                "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
            ]
        )
    )

    static let solarizedLight = AppTheme(
        id: "solarized-light",
        name: "Solarized Light",
        emoji: "🌅",
        isDark: false,
        sidebar: Color(red: 0.933, green: 0.910, blue: 0.835), // #eee8d5
        surface: Color(red: 0.992, green: 0.965, blue: 0.890), // #fdf6e3
        elevated: Color(red: 0.933, green: 0.910, blue: 0.835),
        accent: Color(red: 0.710, green: 0.537, blue: 0.0), // #b58900
        border: Color(red: 0.345, green: 0.431, blue: 0.459).opacity(0.2),
        text: Color(red: 0.345, green: 0.431, blue: 0.459), // #586e75 primary body
        textMuted: Color(red: 0.345, green: 0.431, blue: 0.459).opacity(0.75),
        textFaint: Color(red: 0.345, green: 0.431, blue: 0.459).opacity(0.5),
        hover: Color.black.opacity(0.04),
        selected: Color.black.opacity(0.08),
        canvasBackground: NSColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1),
        accentNSColor: NSColor(red: 0.710, green: 0.537, blue: 0.0, alpha: 0.88),
        terminalTheme: TerminalTheme(
            background: "#fdf6e3",
            foreground: "#586e75",
            cursor: "#657b83",
            selectionBackground: "#eee8d5",
            selectionForeground: "#586e75",
            palette: [
                "#073642", "#dc322f", "#859900", "#b58900",
                "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83",
                "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
            ]
        )
    )

    static let nightBlue = AppTheme(
        id: "night-blue",
        name: "Night Blue",
        emoji: "🌃",
        isDark: true,
        sidebar: Color(red: 0.0, green: 0.110, blue: 0.251), // #001c40
        surface: Color(red: 0.0, green: 0.141, blue: 0.318), // #002451
        elevated: Color(red: 0.0, green: 0.204, blue: 0.431), // #00346e
        accent: Color(red: 0.482, green: 0.753, blue: 1.0), // #7bbcff approx from ansi
        border: Color(red: 0.482, green: 0.753, blue: 1.0).opacity(0.18),
        text: Color(red: 0.8, green: 0.875, blue: 1.0),
        textMuted: Color.white.opacity(0.55),
        textFaint: Color.white.opacity(0.35),
        hover: Color.white.opacity(0.06),
        selected: Color.white.opacity(0.11),
        canvasBackground: NSColor(red: 0.0, green: 0.141, blue: 0.318, alpha: 1),
        accentNSColor: NSColor(red: 0.482, green: 0.753, blue: 1.0, alpha: 0.88),
        terminalTheme: TerminalTheme(
            background: "#002451",
            foreground: "#ffffff",
            cursor: "#99ffff",
            selectionBackground: "#003f8e",
            selectionForeground: "#ffffff",
            palette: [
                "#111111", "#ff9da4", "#d1f1a9", "#ffeead",
                "#bbdaff", "#ebbbff", "#99ffff", "#cccccc",
                "#333333", "#ff7882", "#b8f171", "#ffe580",
                "#80baff", "#d778ff", "#78ffff", "#ffffff",
            ]
        )
    )
}
