import Foundation

extension Optional where Wrapped: RangeReplaceableCollection {
    var orEmpty: Wrapped {
        self ?? .init()
    }
}

extension Optional where Wrapped: ExpressibleByDictionaryLiteral {
    var orEmpty: Wrapped {
        self ?? [:]
    }
}
