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

// MARK: - Sidebar hover tooltips

/// Horizontal placement so labels stay inside narrow sidebars (avoids clipping at the leading/trailing edges).
enum SidebarTooltipHorizontalAnchor {
    /// Align tooltip’s leading edge to the control’s leading edge (extends to the right).
    case leading
    /// Align tooltip’s trailing edge to the control’s trailing edge (extends to the left).
    case trailing
}

struct SidebarHoverTooltipModifier: ViewModifier {
    private static let verticalOffsetAboveControl: CGFloat = -36
    let text: String
    let theme: AppTheme
    @Binding var isPresented: Bool
    var horizontalAnchor: SidebarTooltipHorizontalAnchor

    func body(content: Content) -> some View {
        content
            .overlay(alignment: horizontalAnchor == .leading ? .topLeading : .topTrailing) {
                if isPresented {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.elevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(theme.border.opacity(0.9), lineWidth: 1)
                                )
                        )
                        .fixedSize()
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                        .offset(y: Self.verticalOffsetAboveControl)
                        .offset(y: Self.verticalOffsetAboveControl)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func sidebarHoverTooltip(
        _ text: String,
        theme: AppTheme,
        isPresented: Binding<Bool>,
        horizontalAnchor: SidebarTooltipHorizontalAnchor = .leading
    ) -> some View {
        modifier(SidebarHoverTooltipModifier(
            text: text,
            theme: theme,
            isPresented: isPresented,
            horizontalAnchor: horizontalAnchor
        ))
    }
}
