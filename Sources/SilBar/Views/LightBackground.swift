import SwiftUI

extension View {
    func lightBackground(cornerRadius: CGFloat = 18) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.primary.opacity(0.08))
        }
    }

    func lightCapsuleBackground() -> some View {
        background {
            Capsule()
                .fill(.primary.opacity(0.08))
        }
    }
}
