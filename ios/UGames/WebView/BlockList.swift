import Foundation

struct BlockList {
    let patterns: [String]

    func contentRuleListJSON() -> String {
        let rules = patterns.map { pattern -> [String: Any] in
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            return [
                "trigger": ["url-filter": ".*\(escaped).*"],
                "action": ["type": "block"]
            ]
        }
        let data = try? JSONSerialization.data(withJSONObject: rules, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func load() -> BlockList {
        guard let url = Bundle.main.url(forResource: "ad-domains", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return BlockList(patterns: [])
        }
        let patterns = raw.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            return trimmed
        }
        return BlockList(patterns: patterns)
    }
}
