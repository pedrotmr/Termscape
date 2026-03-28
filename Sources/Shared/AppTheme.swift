import AppKit
import SwiftUI

// MARK: - Theme definition

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    let isDark: Bool

    // Chrome surfaces
    let sidebar: Color
    let surface: Color
    let elevated: Color

    // Accent
    let accent: Color

    // Structure
    let border: Color

    // Text hierarchy
    let text: Color
    let textMuted: Color
    let textFaint: Color

    // Interactive states
    let hover: Color
    let selected: Color

    // AppKit values for Metal/NSView layer coloring
    let canvasBackground: NSColor
    let accentNSColor: NSColor

    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool { lhs.id == rhs.id }
}

// MARK: - All themes

extension AppTheme {
    static let all: [AppTheme] = [
        // Dark themes
        .obsidian, .tobacco, .dracula, .catppuccin, .aurora, .claude, .gruvbox, .brutalist, .sakura, .nordic,
        // Light themes
        .chalk, .parchment,
    ]

    // MARK: Obsidian — original near-black cool dark
    static let obsidian = AppTheme(
        id: "obsidian",
        name: "Obsidian",
        emoji: "🪨",
        isDark: true,
        sidebar:    Color(red: 0.059, green: 0.059, blue: 0.067),  // #0F0F11
        surface:    Color(red: 0.082, green: 0.082, blue: 0.094),  // #151518
        elevated:   Color(red: 0.106, green: 0.106, blue: 0.122),  // #1B1B1F
        accent:     Color(red: 0.337, green: 0.400, blue: 0.957),  // #5666F4 indigo
        border:     Color.white.opacity(0.07),
        text:       Color.white.opacity(0.88),
        textMuted:  Color.white.opacity(0.42),
        textFaint:  Color.white.opacity(0.24),
        hover:      Color.white.opacity(0.05),
        selected:   Color.white.opacity(0.09),
        canvasBackground: NSColor(red: 0.050, green: 0.050, blue: 0.060, alpha: 1),
        accentNSColor:    NSColor(red: 0.337, green: 0.400, blue: 0.957, alpha: 0.85)
    )

    // MARK: Tobacco — warm charcoal
    static let tobacco = AppTheme(
        id: "tobacco",
        name: "Tobacco",
        emoji: "🍂",
        isDark: true,
        sidebar:    Color(red: 0.141, green: 0.133, blue: 0.133),  // #242222
        surface:    Color(red: 0.125, green: 0.118, blue: 0.110),  // #201E1C
        elevated:   Color(red: 0.176, green: 0.165, blue: 0.165),  // #2D2A2A
        accent:     Color(red: 0.922, green: 0.612, blue: 0.239),  // #EB9C3D amber
        border:     Color.white.opacity(0.09),
        text:       Color.white.opacity(0.92),
        textMuted:  Color.white.opacity(0.58),
        textFaint:  Color.white.opacity(0.36),
        hover:      Color.white.opacity(0.07),
        selected:   Color.white.opacity(0.13),
        canvasBackground: NSColor(red: 0.125, green: 0.118, blue: 0.110, alpha: 1),
        accentNSColor:    NSColor(red: 0.922, green: 0.612, blue: 0.239, alpha: 0.85)
    )

    // MARK: Dracula — the iconic purple vampire theme
    // Official palette: https://draculatheme.com
    static let dracula = AppTheme(
        id: "dracula",
        name: "Dracula",
        emoji: "🧛",
        isDark: true,
        sidebar:    Color(red: 0.129, green: 0.133, blue: 0.173),  // #21222C darker bg
        surface:    Color(red: 0.157, green: 0.165, blue: 0.212),  // #282A36 background
        elevated:   Color(red: 0.267, green: 0.278, blue: 0.353),  // #44475A current line
        accent:     Color(red: 0.741, green: 0.576, blue: 0.976),  // #BD93F9 purple
        border:     Color(red: 0.384, green: 0.447, blue: 0.643).opacity(0.30),  // #6272A4 comment
        text:       Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.92),  // #F8F8F2
        textMuted:  Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.55),
        textFaint:  Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.32),
        hover:      Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.08),
        selected:   Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.16),
        canvasBackground: NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1),
        accentNSColor:    NSColor(red: 0.741, green: 0.576, blue: 0.976, alpha: 0.85)
    )

    // MARK: Catppuccin — Mocha, the most beloved modern dark theme
    // Official palette: https://catppuccin.com
    static let catppuccin = AppTheme(
        id: "catppuccin",
        name: "Catppuccin",
        emoji: "🐱",
        isDark: true,
        sidebar:    Color(red: 0.118, green: 0.118, blue: 0.180),  // #1E1E2E base
        surface:    Color(red: 0.094, green: 0.094, blue: 0.145),  // #181825 mantle
        elevated:   Color(red: 0.192, green: 0.196, blue: 0.267),  // #313244 surface0
        accent:     Color(red: 0.796, green: 0.651, blue: 0.969),  // #CBA6F7 mauve
        border:     Color(red: 0.271, green: 0.278, blue: 0.353).opacity(0.55),  // #45475A surface1
        text:       Color(red: 0.804, green: 0.839, blue: 0.957).opacity(0.92),  // #CDD6F4
        textMuted:  Color(red: 0.804, green: 0.839, blue: 0.957).opacity(0.52),
        textFaint:  Color(red: 0.804, green: 0.839, blue: 0.957).opacity(0.28),
        hover:      Color(red: 0.796, green: 0.651, blue: 0.969).opacity(0.07),
        selected:   Color(red: 0.796, green: 0.651, blue: 0.969).opacity(0.15),
        canvasBackground: NSColor(red: 0.094, green: 0.094, blue: 0.145, alpha: 1),
        accentNSColor:    NSColor(red: 0.796, green: 0.651, blue: 0.969, alpha: 0.85)
    )

    // MARK: Aurora — futuristic deep space cyan
    static let aurora = AppTheme(
        id: "aurora",
        name: "Aurora",
        emoji: "🌌",
        isDark: true,
        sidebar:    Color(red: 0.063, green: 0.082, blue: 0.118),  // #101528 navy
        surface:    Color(red: 0.039, green: 0.055, blue: 0.086),  // #0A0E16
        elevated:   Color(red: 0.094, green: 0.122, blue: 0.176),  // #181F2D
        accent:     Color(red: 0.000, green: 0.847, blue: 1.000),  // #00D8FF electric cyan
        border:     Color(red: 0.000, green: 0.847, blue: 1.000).opacity(0.16),
        text:       Color(red: 0.745, green: 0.886, blue: 1.000).opacity(0.92),
        textMuted:  Color(red: 0.745, green: 0.886, blue: 1.000).opacity(0.55),
        textFaint:  Color(red: 0.745, green: 0.886, blue: 1.000).opacity(0.30),
        hover:      Color(red: 0.000, green: 0.847, blue: 1.000).opacity(0.07),
        selected:   Color(red: 0.000, green: 0.847, blue: 1.000).opacity(0.14),
        canvasBackground: NSColor(red: 0.039, green: 0.055, blue: 0.086, alpha: 1),
        accentNSColor:    NSColor(red: 0.000, green: 0.847, blue: 1.000, alpha: 0.85)
    )

    // MARK: Claude — dark mode inspired by Anthropic's warm brand
    // Deep espresso tones + Claude's signature terracotta orange
    static let claude = AppTheme(
        id: "claude",
        name: "Claude",
        emoji: "✳️",
        isDark: true,
        sidebar:    Color(red: 0.114, green: 0.094, blue: 0.082),  // #1D1815 espresso
        surface:    Color(red: 0.082, green: 0.067, blue: 0.055),  // #15110E
        elevated:   Color(red: 0.161, green: 0.133, blue: 0.114),  // #29221D
        accent:     Color(red: 0.855, green: 0.467, blue: 0.337),  // #DA7756 terracotta
        border:     Color(red: 0.855, green: 0.467, blue: 0.337).opacity(0.14),
        text:       Color(red: 0.961, green: 0.922, blue: 0.886).opacity(0.92),  // #F5EBE2 warm white
        textMuted:  Color(red: 0.961, green: 0.922, blue: 0.886).opacity(0.54),
        textFaint:  Color(red: 0.961, green: 0.922, blue: 0.886).opacity(0.30),
        hover:      Color(red: 0.855, green: 0.467, blue: 0.337).opacity(0.09),
        selected:   Color(red: 0.855, green: 0.467, blue: 0.337).opacity(0.18),
        canvasBackground: NSColor(red: 0.082, green: 0.067, blue: 0.055, alpha: 1),
        accentNSColor:    NSColor(red: 0.855, green: 0.467, blue: 0.337, alpha: 0.85)
    )

    // MARK: Gruvbox — warm retro earthy dark
    // Official palette: https://github.com/morhetz/gruvbox
    static let gruvbox = AppTheme(
        id: "gruvbox",
        name: "Gruvbox",
        emoji: "🪵",
        isDark: true,
        sidebar:    Color(red: 0.157, green: 0.157, blue: 0.157),  // #282828 bg
        surface:    Color(red: 0.114, green: 0.125, blue: 0.129),  // #1D2021 bg hard
        elevated:   Color(red: 0.235, green: 0.220, blue: 0.212),  // #3C3836 bg1
        accent:     Color(red: 0.996, green: 0.502, blue: 0.098),  // #FE8019 bright orange
        border:     Color(red: 0.247, green: 0.220, blue: 0.196).opacity(0.70),  // #3F3733
        text:       Color(red: 0.922, green: 0.859, blue: 0.698).opacity(0.92),  // #EBDBB2 fg
        textMuted:  Color(red: 0.659, green: 0.600, blue: 0.518).opacity(0.90),  // #A89984 fg4
        textFaint:  Color(red: 0.922, green: 0.859, blue: 0.698).opacity(0.30),
        hover:      Color(red: 0.996, green: 0.502, blue: 0.098).opacity(0.08),
        selected:   Color(red: 0.996, green: 0.502, blue: 0.098).opacity(0.15),
        canvasBackground: NSColor(red: 0.114, green: 0.125, blue: 0.129, alpha: 1),
        accentNSColor:    NSColor(red: 0.996, green: 0.502, blue: 0.098, alpha: 0.85)
    )

    // MARK: Brutalist — raw, high-contrast, uncompromising
    static let brutalist = AppTheme(
        id: "brutalist",
        name: "Brutalist",
        emoji: "⬛",
        isDark: true,
        sidebar:    Color(red: 0.063, green: 0.063, blue: 0.063),  // #101010
        surface:    Color(red: 0.047, green: 0.047, blue: 0.047),  // #0C0C0C
        elevated:   Color(red: 0.094, green: 0.094, blue: 0.094),  // #181818
        accent:     Color(red: 1.000, green: 0.231, blue: 0.188),  // #FF3B30 red
        border:     Color.white.opacity(0.18),
        text:       Color.white.opacity(1.00),
        textMuted:  Color.white.opacity(0.68),
        textFaint:  Color.white.opacity(0.42),
        hover:      Color.white.opacity(0.08),
        selected:   Color.white.opacity(0.16),
        canvasBackground: NSColor(red: 0.047, green: 0.047, blue: 0.047, alpha: 1),
        accentNSColor:    NSColor(red: 1.000, green: 0.231, blue: 0.188, alpha: 0.85)
    )

    // MARK: Sakura — playful dark plum
    static let sakura = AppTheme(
        id: "sakura",
        name: "Sakura",
        emoji: "🌸",
        isDark: true,
        sidebar:    Color(red: 0.165, green: 0.122, blue: 0.200),  // #2A1F33 plum
        surface:    Color(red: 0.118, green: 0.082, blue: 0.157),  // #1E1528
        elevated:   Color(red: 0.208, green: 0.149, blue: 0.251),  // #352640
        accent:     Color(red: 1.000, green: 0.420, blue: 0.616),  // #FF6B9D hot pink
        border:     Color(red: 1.000, green: 0.420, blue: 0.616).opacity(0.16),
        text:       Color.white.opacity(0.92),
        textMuted:  Color.white.opacity(0.62),
        textFaint:  Color.white.opacity(0.38),
        hover:      Color(red: 1.000, green: 0.420, blue: 0.616).opacity(0.08),
        selected:   Color(red: 1.000, green: 0.420, blue: 0.616).opacity(0.16),
        canvasBackground: NSColor(red: 0.118, green: 0.082, blue: 0.157, alpha: 1),
        accentNSColor:    NSColor(red: 1.000, green: 0.420, blue: 0.616, alpha: 0.85)
    )

    // MARK: Nordic — minimal Nord-inspired polar night
    static let nordic = AppTheme(
        id: "nordic",
        name: "Nordic",
        emoji: "🏔️",
        isDark: true,
        sidebar:    Color(red: 0.180, green: 0.204, blue: 0.251),  // #2E3440
        surface:    Color(red: 0.141, green: 0.161, blue: 0.200),  // #242933
        elevated:   Color(red: 0.231, green: 0.259, blue: 0.322),  // #3B4252
        accent:     Color(red: 0.533, green: 0.753, blue: 0.816),  // #88C0D0 frost
        border:     Color.white.opacity(0.10),
        text:       Color(red: 0.929, green: 0.937, blue: 0.957).opacity(0.90),  // #ECEFF4
        textMuted:  Color(red: 0.929, green: 0.937, blue: 0.957).opacity(0.55),
        textFaint:  Color(red: 0.929, green: 0.937, blue: 0.957).opacity(0.32),
        hover:      Color.white.opacity(0.07),
        selected:   Color.white.opacity(0.12),
        canvasBackground: NSColor(red: 0.141, green: 0.161, blue: 0.200, alpha: 1),
        accentNSColor:    NSColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 0.85)
    )

    // MARK: Chalk — refined paper white, quality writing surface
    // Warm stone sidebar with ivory surface — not plain white, not parchment
    static let chalk = AppTheme(
        id: "chalk",
        name: "Chalk",
        emoji: "🕯️",
        isDark: false,
        sidebar:    Color(red: 0.831, green: 0.816, blue: 0.796),  // #D4D0CB warm stone
        surface:    Color(red: 0.929, green: 0.918, blue: 0.902),  // #EDEAD6 warm paper
        elevated:   Color(red: 0.969, green: 0.961, blue: 0.949),  // #F7F5F2 warm ivory
        accent:     Color(red: 0.337, green: 0.400, blue: 0.957),  // #5666F4 indigo
        border:     Color(red: 0.239, green: 0.169, blue: 0.102).opacity(0.09),
        text:       Color(red: 0.102, green: 0.071, blue: 0.035).opacity(0.84),  // warm near-black
        textMuted:  Color(red: 0.102, green: 0.071, blue: 0.035).opacity(0.50),
        textFaint:  Color(red: 0.102, green: 0.071, blue: 0.035).opacity(0.28),
        hover:      Color(red: 0.239, green: 0.169, blue: 0.102).opacity(0.055),
        selected:   Color(red: 0.239, green: 0.169, blue: 0.102).opacity(0.095),
        canvasBackground: NSColor(red: 0.898, green: 0.882, blue: 0.859, alpha: 1),
        accentNSColor:    NSColor(red: 0.337, green: 0.400, blue: 0.957, alpha: 0.85)
    )

    // MARK: Parchment — warm cream inspired by Claude's light interface
    // Aged paper warmth with terracotta orange accent
    static let parchment = AppTheme(
        id: "parchment",
        name: "Parchment",
        emoji: "📜",
        isDark: false,
        sidebar:    Color(red: 0.902, green: 0.882, blue: 0.851),  // #E6E1D9 warm parchment sidebar
        surface:    Color(red: 0.949, green: 0.929, blue: 0.898),  // #F2EDE5 cream surface
        elevated:   Color(red: 0.980, green: 0.965, blue: 0.941),  // #FAF6F0 warm near-white
        accent:     Color(red: 0.788, green: 0.420, blue: 0.243),  // #C96B3E terracotta
        border:     Color(red: 0.290, green: 0.188, blue: 0.094).opacity(0.10),
        text:       Color(red: 0.118, green: 0.071, blue: 0.031).opacity(0.84),  // #1E1208 warm brown
        textMuted:  Color(red: 0.118, green: 0.071, blue: 0.031).opacity(0.50),
        textFaint:  Color(red: 0.118, green: 0.071, blue: 0.031).opacity(0.28),
        hover:      Color(red: 0.290, green: 0.188, blue: 0.094).opacity(0.06),
        selected:   Color(red: 0.290, green: 0.188, blue: 0.094).opacity(0.11),
        canvasBackground: NSColor(red: 0.929, green: 0.906, blue: 0.875, alpha: 1),
        accentNSColor:    NSColor(red: 0.788, green: 0.420, blue: 0.243, alpha: 0.85)
    )
}
