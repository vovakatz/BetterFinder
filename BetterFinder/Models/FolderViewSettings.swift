import Foundation

struct FolderViewSettings: Codable, Equatable {
    var viewMode: ViewMode?
    var sortCriteria: SortCriteria?
    var showHiddenFiles: Bool?

    var isEmpty: Bool {
        viewMode == nil && sortCriteria == nil && showHiddenFiles == nil
    }
}
