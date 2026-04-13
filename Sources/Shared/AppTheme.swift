import AppKit
import SwiftUI

// MARK: - Terminal color palette

struct TerminalTheme {
  let background: String
  let foreground: String
  let cursor: String
  let selectionBackground: String
  let selectionForeground: String
  /// Exactly 16 ANSI colors (indices 0–15)
  let palette: [String]
}

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

  // Terminal color palette applied to Ghostty on theme change
  let terminalTheme: TerminalTheme

  static func == (lhs: AppTheme, rhs: AppTheme) -> Bool { lhs.id == rhs.id }

  /// Recessed void behind floating terminal panes (gutters); derived from `canvasBackground`.
  var canvasMatte: NSColor {
    guard let c = canvasBackground.usingColorSpace(.deviceRGB) else { return canvasBackground }
    if isDark {
      return NSColor(
        red: max(0, c.redComponent * 0.42),
        green: max(0, c.greenComponent * 0.42),
        blue: max(0, c.blueComponent * 0.45),
        alpha: 1
      )
    }
    return NSColor(
      red: max(0, min(1, c.redComponent - 0.035)),
      green: max(0, min(1, c.greenComponent - 0.035)),
      blue: max(0, min(1, c.blueComponent - 0.035)),
      alpha: 1
    )
  }
}

// MARK: - All themes

extension AppTheme {
  static let all: [AppTheme] = [
    // Dark
    .obsidian, .tobacco, .dracula, .catppuccin, .aurora, .claude, .gruvbox, .brutalist, .sakura,
    .nordic,
    // Light
    .chalk, .parchment,
  ]

  // MARK: Obsidian — original near-black cool dark
  static let obsidian = AppTheme(
    id: "obsidian",
    name: "Obsidian",
    emoji: "🪨",
    isDark: true,
    sidebar: Color(red: 0.059, green: 0.059, blue: 0.067),
    surface: Color(red: 0.082, green: 0.082, blue: 0.094),
    elevated: Color(red: 0.106, green: 0.106, blue: 0.122),
    accent: Color(red: 0.337, green: 0.400, blue: 0.957),  // #5666F4
    border: Color.white.opacity(0.07),
    text: Color.white.opacity(0.88),
    textMuted: Color.white.opacity(0.42),
    textFaint: Color.white.opacity(0.24),
    hover: Color.white.opacity(0.05),
    selected: Color.white.opacity(0.09),
    canvasBackground: NSColor(red: 0.050, green: 0.050, blue: 0.060, alpha: 1),
    accentNSColor: NSColor(red: 0.337, green: 0.400, blue: 0.957, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#0F0F11",
      foreground: "#E0E0E8",
      cursor: "#5666F4",
      selectionBackground: "#2A2A38",
      selectionForeground: "#E0E0E8",
      palette: [
        "#1A1A1F", "#FF5F5F", "#5FAFA3", "#D7AF5F",
        "#5666F4", "#9B78D4", "#5FAFAF", "#C8C8D0",
        "#2E2E3A", "#FF7F7F", "#6FCFBF", "#EFCF7F",
        "#7080FF", "#BF98F4", "#7FCFCF", "#E0E0E8",
      ]
    )
  )

  // MARK: Tobacco — warm charcoal
  static let tobacco = AppTheme(
    id: "tobacco",
    name: "Tobacco",
    emoji: "🍂",
    isDark: true,
    sidebar: Color(red: 0.141, green: 0.133, blue: 0.133),
    surface: Color(red: 0.125, green: 0.118, blue: 0.110),
    elevated: Color(red: 0.176, green: 0.165, blue: 0.165),
    accent: Color(red: 0.922, green: 0.612, blue: 0.239),  // #EB9C3D
    border: Color.white.opacity(0.09),
    text: Color.white.opacity(0.92),
    textMuted: Color.white.opacity(0.58),
    textFaint: Color.white.opacity(0.36),
    hover: Color.white.opacity(0.07),
    selected: Color.white.opacity(0.13),
    canvasBackground: NSColor(red: 0.125, green: 0.118, blue: 0.110, alpha: 1),
    accentNSColor: NSColor(red: 0.922, green: 0.612, blue: 0.239, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#201E1C",
      foreground: "#E8DDD0",
      cursor: "#EB9C3D",
      selectionBackground: "#352F28",
      selectionForeground: "#E8DDD0",
      palette: [
        "#1A1714", "#D47060", "#8BA870", "#EB9C3D",
        "#6880C8", "#A878A0", "#70A8A0", "#C8B8A0",
        "#2E2820", "#E88070", "#A0C080", "#FFBC5D",
        "#80A0E8", "#C890C0", "#90C8C0", "#E8DDD0",
      ]
    )
  )

  // MARK: Dracula — the iconic purple vampire theme
  static let dracula = AppTheme(
    id: "dracula",
    name: "Dracula",
    emoji: "🧛",
    isDark: true,
    sidebar: Color(red: 0.129, green: 0.133, blue: 0.173),
    surface: Color(red: 0.157, green: 0.165, blue: 0.212),
    elevated: Color(red: 0.267, green: 0.278, blue: 0.353),
    accent: Color(red: 0.741, green: 0.576, blue: 0.976),  // #BD93F9
    border: Color(red: 0.384, green: 0.447, blue: 0.643).opacity(0.30),
    text: Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.92),
    textMuted: Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.55),
    textFaint: Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.32),
    hover: Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.08),
    selected: Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.16),
    canvasBackground: NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1),
    accentNSColor: NSColor(red: 0.741, green: 0.576, blue: 0.976, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#282A36",
      foreground: "#F8F8F2",
      cursor: "#F8F8F2",
      selectionBackground: "#44475A",
      selectionForeground: "#F8F8F2",
      palette: [
        "#21222C", "#FF5555", "#50FA7B", "#F1FA8C",
        "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
        "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5",
        "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF",
      ]
    )
  )

  // MARK: Catppuccin — Mocha, the beloved modern dark theme
  static let catppuccin = AppTheme(
    id: "catppuccin",
    name: "Catppuccin",
    emoji: "🐱",
    isDark: true,
    sidebar: Color(red: 0.118, green: 0.118, blue: 0.180),
    surface: Color(red: 0.094, green: 0.094, blue: 0.145),
    elevated: Color(red: 0.192, green: 0.196, blue: 0.267),
    accent: Color(red: 0.796, green: 0.651, blue: 0.969),  // #CBA6F7
    border: Color(red: 0.271, green: 0.278, blue: 0.353).opacity(0.55),
    text: Color(red: 0.804, green: 0.839, blue: 0.957).opacity(0.92),
    textMuted: Color(red: 0.804, green: 0.839, blue: 0.957).opacity(0.52),
    textFaint: Color(red: 0.804, green: 0.839, blue: 0.957).opacity(0.28),
    hover: Color(red: 0.796, green: 0.651, blue: 0.969).opacity(0.07),
    selected: Color(red: 0.796, green: 0.651, blue: 0.969).opacity(0.15),
    canvasBackground: NSColor(red: 0.094, green: 0.094, blue: 0.145, alpha: 1),
    accentNSColor: NSColor(red: 0.796, green: 0.651, blue: 0.969, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#1E1E2E",
      foreground: "#CDD6F4",
      cursor: "#F5E0DC",
      selectionBackground: "#585B70",
      selectionForeground: "#CDD6F4",
      palette: [
        "#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF",
        "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE",
        "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF",
        "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8",
      ]
    )
  )

  // MARK: Aurora — futuristic deep space cyan
  static let aurora = AppTheme(
    id: "aurora",
    name: "Aurora",
    emoji: "🌌",
    isDark: true,
    sidebar: Color(red: 0.063, green: 0.082, blue: 0.118),
    surface: Color(red: 0.039, green: 0.055, blue: 0.086),
    elevated: Color(red: 0.094, green: 0.122, blue: 0.176),
    accent: Color(red: 0.000, green: 0.847, blue: 1.000),  // #00D8FF
    border: Color(red: 0.000, green: 0.847, blue: 1.000).opacity(0.16),
    text: Color(red: 0.745, green: 0.886, blue: 1.000).opacity(0.92),
    textMuted: Color(red: 0.745, green: 0.886, blue: 1.000).opacity(0.55),
    textFaint: Color(red: 0.745, green: 0.886, blue: 1.000).opacity(0.30),
    hover: Color(red: 0.000, green: 0.847, blue: 1.000).opacity(0.07),
    selected: Color(red: 0.000, green: 0.847, blue: 1.000).opacity(0.14),
    canvasBackground: NSColor(red: 0.039, green: 0.055, blue: 0.086, alpha: 1),
    accentNSColor: NSColor(red: 0.000, green: 0.847, blue: 1.000, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#0A0E16",
      foreground: "#BEE2FF",
      cursor: "#00D8FF",
      selectionBackground: "#1A2A3A",
      selectionForeground: "#BEE2FF",
      palette: [
        "#0D1520", "#FF4A6E", "#00E5B0", "#FFD080",
        "#00D8FF", "#C880FF", "#00EEFF", "#8FC8E8",
        "#1A2A3A", "#FF6A8E", "#00FFCA", "#FFE0A0",
        "#60F0FF", "#E0A0FF", "#60FFFF", "#BEE2FF",
      ]
    )
  )

  // MARK: Claude — dark espresso + Anthropic terracotta
  static let claude = AppTheme(
    id: "claude",
    name: "Claude",
    emoji: "✳️",
    isDark: true,
    sidebar: Color(red: 0.114, green: 0.094, blue: 0.082),
    surface: Color(red: 0.082, green: 0.067, blue: 0.055),
    elevated: Color(red: 0.161, green: 0.133, blue: 0.114),
    accent: Color(red: 0.855, green: 0.467, blue: 0.337),  // #DA7756
    border: Color(red: 0.855, green: 0.467, blue: 0.337).opacity(0.14),
    text: Color(red: 0.961, green: 0.922, blue: 0.886).opacity(0.92),
    textMuted: Color(red: 0.961, green: 0.922, blue: 0.886).opacity(0.54),
    textFaint: Color(red: 0.961, green: 0.922, blue: 0.886).opacity(0.30),
    hover: Color(red: 0.855, green: 0.467, blue: 0.337).opacity(0.09),
    selected: Color(red: 0.855, green: 0.467, blue: 0.337).opacity(0.18),
    canvasBackground: NSColor(red: 0.082, green: 0.067, blue: 0.055, alpha: 1),
    accentNSColor: NSColor(red: 0.855, green: 0.467, blue: 0.337, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#15110E",
      foreground: "#F5EBE2",
      cursor: "#DA7756",
      selectionBackground: "#2E2018",
      selectionForeground: "#F5EBE2",
      palette: [
        "#1D1814", "#CF5C4A", "#7EA870", "#D4A060",
        "#6880B0", "#A87898", "#6A9898", "#D0C0B0",
        "#302218", "#DA7756", "#9CC890", "#ECC080",
        "#8898D0", "#C890B0", "#88B8B8", "#F5EBE2",
      ]
    )
  )

  // MARK: Gruvbox — warm retro earthy dark (official palette)
  static let gruvbox = AppTheme(
    id: "gruvbox",
    name: "Gruvbox",
    emoji: "🪵",
    isDark: true,
    sidebar: Color(red: 0.157, green: 0.157, blue: 0.157),
    surface: Color(red: 0.114, green: 0.125, blue: 0.129),
    elevated: Color(red: 0.235, green: 0.220, blue: 0.212),
    accent: Color(red: 0.996, green: 0.502, blue: 0.098),  // #FE8019
    border: Color(red: 0.247, green: 0.220, blue: 0.196).opacity(0.70),
    text: Color(red: 0.922, green: 0.859, blue: 0.698).opacity(0.92),
    textMuted: Color(red: 0.659, green: 0.600, blue: 0.518).opacity(0.90),
    textFaint: Color(red: 0.922, green: 0.859, blue: 0.698).opacity(0.30),
    hover: Color(red: 0.996, green: 0.502, blue: 0.098).opacity(0.08),
    selected: Color(red: 0.996, green: 0.502, blue: 0.098).opacity(0.15),
    canvasBackground: NSColor(red: 0.114, green: 0.125, blue: 0.129, alpha: 1),
    accentNSColor: NSColor(red: 0.996, green: 0.502, blue: 0.098, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#282828",
      foreground: "#EBDBB2",
      cursor: "#FE8019",
      selectionBackground: "#3C3836",
      selectionForeground: "#EBDBB2",
      palette: [
        "#282828", "#CC241D", "#98971A", "#D79921",
        "#458588", "#B16286", "#689D6A", "#A89984",
        "#928374", "#FB4934", "#B8BB26", "#FABD2F",
        "#83A598", "#D3869B", "#8EC07C", "#EBDBB2",
      ]
    )
  )

  // MARK: Brutalist — raw, high-contrast, uncompromising
  static let brutalist = AppTheme(
    id: "brutalist",
    name: "Brutalist",
    emoji: "⬛",
    isDark: true,
    sidebar: Color(red: 0.063, green: 0.063, blue: 0.063),
    surface: Color(red: 0.047, green: 0.047, blue: 0.047),
    elevated: Color(red: 0.094, green: 0.094, blue: 0.094),
    accent: Color(red: 1.000, green: 0.231, blue: 0.188),  // #FF3B30
    border: Color.white.opacity(0.18),
    text: Color.white.opacity(1.00),
    textMuted: Color.white.opacity(0.68),
    textFaint: Color.white.opacity(0.42),
    hover: Color.white.opacity(0.08),
    selected: Color.white.opacity(0.16),
    canvasBackground: NSColor(red: 0.047, green: 0.047, blue: 0.047, alpha: 1),
    accentNSColor: NSColor(red: 1.000, green: 0.231, blue: 0.188, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#0C0C0C",
      foreground: "#FFFFFF",
      cursor: "#FF3B30",
      selectionBackground: "#222222",
      selectionForeground: "#FFFFFF",
      palette: [
        "#111111", "#FF3B30", "#30D158", "#FFD60A",
        "#0A84FF", "#BF5AF2", "#32ADE6", "#EBEBEB",
        "#3A3A3A", "#FF6961", "#4CD964", "#FFE333",
        "#409CFF", "#DA8FFF", "#70D7FF", "#FFFFFF",
      ]
    )
  )

  // MARK: Sakura — playful dark plum
  static let sakura = AppTheme(
    id: "sakura",
    name: "Sakura",
    emoji: "🌸",
    isDark: true,
    sidebar: Color(red: 0.165, green: 0.122, blue: 0.200),
    surface: Color(red: 0.118, green: 0.082, blue: 0.157),
    elevated: Color(red: 0.208, green: 0.149, blue: 0.251),
    accent: Color(red: 1.000, green: 0.420, blue: 0.616),  // #FF6B9D
    border: Color(red: 1.000, green: 0.420, blue: 0.616).opacity(0.16),
    text: Color.white.opacity(0.92),
    textMuted: Color.white.opacity(0.62),
    textFaint: Color.white.opacity(0.38),
    hover: Color(red: 1.000, green: 0.420, blue: 0.616).opacity(0.08),
    selected: Color(red: 1.000, green: 0.420, blue: 0.616).opacity(0.16),
    canvasBackground: NSColor(red: 0.118, green: 0.082, blue: 0.157, alpha: 1),
    accentNSColor: NSColor(red: 1.000, green: 0.420, blue: 0.616, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#1E1528",
      foreground: "#F0E0F0",
      cursor: "#FF6B9D",
      selectionBackground: "#352640",
      selectionForeground: "#F0E0F0",
      palette: [
        "#1A1020", "#FF5B78", "#78D8A0", "#F0C080",
        "#A078E8", "#FF6B9D", "#78D8D8", "#D0B8D8",
        "#2D1E3A", "#FF7B98", "#90EEC0", "#FFD8A0",
        "#C098FF", "#FF90BD", "#90F0F0", "#F0E0F0",
      ]
    )
  )

  // MARK: Nordic — minimal Nord-inspired polar night
  static let nordic = AppTheme(
    id: "nordic",
    name: "Nordic",
    emoji: "🏔️",
    isDark: true,
    sidebar: Color(red: 0.180, green: 0.204, blue: 0.251),
    surface: Color(red: 0.141, green: 0.161, blue: 0.200),
    elevated: Color(red: 0.231, green: 0.259, blue: 0.322),
    accent: Color(red: 0.533, green: 0.753, blue: 0.816),  // #88C0D0
    border: Color.white.opacity(0.10),
    text: Color(red: 0.929, green: 0.937, blue: 0.957).opacity(0.90),
    textMuted: Color(red: 0.929, green: 0.937, blue: 0.957).opacity(0.55),
    textFaint: Color(red: 0.929, green: 0.937, blue: 0.957).opacity(0.32),
    hover: Color.white.opacity(0.07),
    selected: Color.white.opacity(0.12),
    canvasBackground: NSColor(red: 0.141, green: 0.161, blue: 0.200, alpha: 1),
    accentNSColor: NSColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#2E3440",
      foreground: "#D8DEE9",
      cursor: "#88C0D0",
      selectionBackground: "#3B4252",
      selectionForeground: "#D8DEE9",
      palette: [
        "#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B",
        "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
        "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B",
        "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4",
      ]
    )
  )

  // MARK: Chalk — refined warm stone + ivory, quality writing surface
  static let chalk = AppTheme(
    id: "chalk",
    name: "Chalk",
    emoji: "🕯️",
    isDark: false,
    sidebar: Color(red: 0.831, green: 0.816, blue: 0.796),
    surface: Color(red: 0.929, green: 0.918, blue: 0.902),
    elevated: Color(red: 0.969, green: 0.961, blue: 0.949),
    accent: Color(red: 0.337, green: 0.400, blue: 0.957),  // #5666F4
    border: Color(red: 0.239, green: 0.169, blue: 0.102).opacity(0.09),
    text: Color(red: 0.102, green: 0.071, blue: 0.035).opacity(0.84),
    textMuted: Color(red: 0.102, green: 0.071, blue: 0.035).opacity(0.50),
    textFaint: Color(red: 0.102, green: 0.071, blue: 0.035).opacity(0.28),
    hover: Color(red: 0.239, green: 0.169, blue: 0.102).opacity(0.055),
    selected: Color(red: 0.239, green: 0.169, blue: 0.102).opacity(0.095),
    canvasBackground: NSColor(red: 0.898, green: 0.882, blue: 0.859, alpha: 1),
    accentNSColor: NSColor(red: 0.337, green: 0.400, blue: 0.957, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#EDEAD6",
      foreground: "#1A1209",
      cursor: "#5666F4",
      selectionBackground: "#D9D3C9",
      selectionForeground: "#1A1209",
      palette: [
        "#2C2018", "#C0392B", "#27AE60", "#D4870A",
        "#2E5FAB", "#8E44AD", "#16A085", "#746A60",
        "#5C4A38", "#E74C3C", "#2ECC71", "#F39C12",
        "#3498DB", "#9B59B6", "#1ABC9C", "#1A1209",
      ]
    )
  )

  // MARK: Parchment — warm cream matching Claude's light interface
  static let parchment = AppTheme(
    id: "parchment",
    name: "Parchment",
    emoji: "📜",
    isDark: false,
    sidebar: Color(red: 0.902, green: 0.882, blue: 0.851),
    surface: Color(red: 0.949, green: 0.929, blue: 0.898),
    elevated: Color(red: 0.980, green: 0.965, blue: 0.941),
    accent: Color(red: 0.788, green: 0.420, blue: 0.243),  // #C96B3E
    border: Color(red: 0.290, green: 0.188, blue: 0.094).opacity(0.10),
    text: Color(red: 0.118, green: 0.071, blue: 0.031).opacity(0.84),
    textMuted: Color(red: 0.118, green: 0.071, blue: 0.031).opacity(0.50),
    textFaint: Color(red: 0.118, green: 0.071, blue: 0.031).opacity(0.28),
    hover: Color(red: 0.290, green: 0.188, blue: 0.094).opacity(0.06),
    selected: Color(red: 0.290, green: 0.188, blue: 0.094).opacity(0.11),
    canvasBackground: NSColor(red: 0.929, green: 0.906, blue: 0.875, alpha: 1),
    accentNSColor: NSColor(red: 0.788, green: 0.420, blue: 0.243, alpha: 0.85),
    terminalTheme: TerminalTheme(
      background: "#F2EDE5",
      foreground: "#1E1208",
      cursor: "#C96B3E",
      selectionBackground: "#E6E1D9",
      selectionForeground: "#1E1208",
      palette: [
        "#2C1F0F", "#B83030", "#3D7A40", "#B87030",
        "#3050A0", "#784080", "#307878", "#6E5840",
        "#4E3820", "#C94040", "#509A55", "#C89040",
        "#5070C0", "#9858A0", "#509898", "#1E1208",
      ]
    )
  )
}
