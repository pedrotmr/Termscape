import AppKit
import Foundation
import SwiftUI

// MARK: - Button styles

struct MuxonPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(ThemeManager.self) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? .white : theme.current.textFaint)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(isEnabled ? theme.current.accent : theme.current.hover)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.75 : 1.0)
    }
}

struct MuxonSecondaryButtonStyle: ButtonStyle {
    @Environment(ThemeManager.self) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(theme.current.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isHovered ? theme.current.hover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.current.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .onHover { isHovered = $0 }
    }
}

// MARK: - NSScreen helpers

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(id.uint32Value)
    }
}

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized = String(sanitized.dropFirst()) }
        guard sanitized.count == 6, let rgb = UInt64(sanitized, radix: 16) else {
            self.init(red: 0, green: 0, blue: 0)
            return
        }
        self.init(
            red:   Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8)  / 255.0,
            blue:  Double( rgb & 0x0000FF)         / 255.0
        )
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
