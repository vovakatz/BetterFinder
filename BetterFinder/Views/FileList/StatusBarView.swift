import SwiftUI

/// Isolates selectedItems observation from ContentView so that selection
/// changes only re-evaluate this small view, not the entire layout.
struct StatusBarContainer: View {
    var viewModel: FileListViewModel

    var body: some View {
        StatusBarView(
            selectionCount: viewModel.selectionCount,
            volumeStatusText: viewModel.volumeStatusText
        )
    }
}

struct StatusBarView: View {
    let selectionCount: Int
    let volumeStatusText: String

    var body: some View {
        HStack {
            if selectionCount > 0 {
                Text("\(selectionCount) items selected")
            }
            Spacer()
            Text(volumeStatusText)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.08))
    }
}
