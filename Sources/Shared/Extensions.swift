import AppKit
import Foundation
import SwiftUI

// MARK: - Design tokens

extension Color {
    static let muxSidebar    = Color(red: 0.059, green: 0.059, blue: 0.067)  // #0F0F11
    static let muxSurface    = Color(red: 0.082, green: 0.082, blue: 0.094)  // #151518
    static let muxElevated   = Color(red: 0.106, green: 0.106, blue: 0.122)  // #1B1B1F
    static let muxAccent     = Color(red: 0.337, green: 0.400, blue: 0.957)  // #5666F4
    static let muxBorder     = Color.white.opacity(0.07)
    static let muxText       = Color.white.opacity(0.88)
    static let muxTextMuted  = Color.white.opacity(0.42)
    static let muxTextFaint  = Color.white.opacity(0.24)
    static let muxHover      = Color.white.opacity(0.05)
    static let muxSelected   = Color.white.opacity(0.09)
}

// MARK: - Button styles

struct MuxonPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? .white : Color.white.opacity(0.3))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(isEnabled ? Color.muxAccent : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.75 : 1.0)
    }
}

struct MuxonSecondaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.muxBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .onHover { isHovered = $0 }
    }
}

extension NSScreen {
    /// The CGDirectDisplayID for this screen, used for Ghostty display tracking.
    var displayID: CGDirectDisplayID? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(id.uint32Value)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    func hexString() -> String {
        guard let color = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(color.redComponent * 255)
        let g = Int(color.greenComponent * 255)
        let b = Int(color.blueComponent * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
