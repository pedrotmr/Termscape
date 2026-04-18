import SwiftUI

/// Reusable 1px divider for horizontal width resizing with clamped bounds.
struct HorizontalResizeDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let idleColor: Color
    let hoverColor: Color
    var hitSlop: CGFloat = 4
    var hoverAnimationDuration: Double = 0.15

    @State private var isHovered = false
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(isHovered ? hoverColor : idleColor)
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -hitSlop))
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: hoverAnimationDuration), value: isHovered)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let base = dragStartWidth ?? width
                        let proposed = base + value.translation.width
                        let clamped = proposed.clamped(to: minWidth ... maxWidth)
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            width = clamped
                        }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .cursor(.resizeLeftRight)
    }
}
