import Foundation

extension Sequence {
    func dedupeBy<Key: Hashable>(_ key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        var out: [Element] = []
        for element in self {
            if seen.insert(key(element)).inserted {
                out.append(element)
            }
        }
        return out
    }
}

extension Array {
    mutating func appendUnique<S: Sequence, Key: Hashable>(
        contentsOf newElements: S,
        by key: (Element) -> Key
    ) where S.Element == Element {
        var seen = Set(map(key))
        for element in newElements {
            if seen.insert(key(element)).inserted {
                append(element)
            }
        }
    }
}
