import Foundation

enum SortField: String, CaseIterable, Codable {
    case name
    case dateModified
    case size
    case kind
}

struct SortCriteria: Equatable, Codable {
    var field: SortField = .name
    var ascending: Bool = true

    static let `default` = SortCriteria()
}
