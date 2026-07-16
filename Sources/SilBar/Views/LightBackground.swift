import SwiftUI

extension View {
    func lightBackground(cornerRadius: CGFloat = 18) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.primary.opacity(0.08))
        }
    }

    func hoverableLightBackground(cornerRadius: CGFloat = 18) -> some View {
        modifier(HoverableLightBackground(cornerRadius: cornerRadius))
    }

    func lightCapsuleBackground() -> some View {
        background {
            Capsule()
                .fill(.primary.opacity(0.08))
        }
    }
}

private struct HoverableLightBackground: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(isHovered ? 0.13 : 0.08))
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
