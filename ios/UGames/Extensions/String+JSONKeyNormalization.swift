import Foundation

extension String {
    var normalizedJSONKey: String {
        let parts = split(whereSeparator: { $0 == "_" || $0 == "-" })
        guard parts.count > 1 else { return self }
        let head = String(parts[0])
        let tail = parts.dropFirst().map { part -> String in
            let value = String(part)
            guard let first = value.first else { return value }
            return String(first).uppercased() + value.dropFirst()
        }
        return ([head] + tail).joined()
    }
}
