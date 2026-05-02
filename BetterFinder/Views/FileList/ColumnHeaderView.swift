import SwiftUI
import AppKit

struct ColumnHeaderView: View {
    let sortCriteria: SortCriteria
    let onSort: (SortField) -> Void
    @Binding var dateWidth: CGFloat
    @Binding var sizeWidth: CGFloat
    @Binding var kindWidth: CGFloat
    var effectiveDateWidth: CGFloat = 150
    var effectiveSizeWidth: CGFloat = 80
    var effectiveKindWidth: CGFloat = 120
    /// Leading/trailing padding to align with row content. Should equal the
    /// total visual leading offset of List rows (List intrinsic inset +
    /// `.listRowInsets(.leading)`). See `FileListLayout` in `FileListView.swift`.
    var horizontalPadding: CGFloat = 8

    @State private var startWidths: (date: CGFloat, size: CGFloat, kind: CGFloat)?

    var body: some View {
        HStack(spacing: 0) {
            headerButton("Name", field: .name)
                .frame(maxWidth: .infinity, alignment: .leading)

            columnResizeHandle { translation in
                guard let start = startWidths else { return }
                dateWidth = max(60, start.date - translation)
            }

            headerButton("Date Modified", field: .dateModified)
                .frame(width: effectiveDateWidth, alignment: .leading)

            columnResizeHandle { translation in
                guard let start = startWidths else { return }
                dateWidth = max(60, start.date + translation)
                sizeWidth = max(40, start.size - translation)
            }

            headerButton("Size", field: .size)
                .frame(width: effectiveSizeWidth, alignment: .trailing)

            columnResizeHandle { translation in
                guard let start = startWidths else { return }
                sizeWidth = max(40, start.size + translation)
                kindWidth = max(60, start.kind - translation)
            }

            headerButton("Kind", field: .kind)
                .frame(width: effectiveKindWidth, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, horizontalPadding)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func columnResizeHandle(
        onDrag: @escaping (CGFloat) -> Void
    ) -> some View {
        Color.clear
            .frame(width: 8, height: 16)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if startWidths == nil {
                            startWidths = (dateWidth, sizeWidth, kindWidth)
                        }
                        onDrag(value.translation.width)
                    }
                    .onEnded { _ in
                        startWidths = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func headerButton(_ title: String, field: SortField) -> some View {
        Button {
            onSort(field)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Spacer()
                if sortCriteria.field == field {
                    Image(systemName: sortCriteria.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
