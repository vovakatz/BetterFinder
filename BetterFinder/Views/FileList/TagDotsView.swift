import SwiftUI

/// Trailing colored circles next to a filename, one per tag.
/// Hidden entirely when `tags` is empty (no layout space reserved).
struct TagDotsView: View {
    let tags: [FileTag]

    private static let dotDiameter: CGFloat = 11
    private static let dotOverlap: CGFloat = 2
    private static let maxDots: Int = 3

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            let visible = Array(tags.prefix(Self.maxDots))
            HStack(spacing: -Self.dotOverlap) {
                ForEach(Array(visible.enumerated()), id: \.element.name) { _, tag in
                    dot(for: tag)
                }
            }
            .help(tags.map(\.name).joined(separator: ", "))
        }
    }

    @ViewBuilder
    private func dot(for tag: FileTag) -> some View {
        if tag.color.rendersAsRing {
            Circle()
                .strokeBorder(Color.gray.opacity(0.6), lineWidth: 1)
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
        } else {
            Circle()
                .fill(tag.color.swiftUIColor)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .frame(width: Self.dotDiameter, height: Self.dotDiameter)
        }
    }
}
