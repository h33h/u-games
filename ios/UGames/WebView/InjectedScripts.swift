import Foundation

struct InjectedScripts {
    let honestPath: String
    let pwaModeJs: String
    let pwaModeCss: String
    let sdkStub: String

    var mainFrameScript: String {
        let cssLiteral = jsString(pwaModeCss)
        return """
        window.__yga_pwa_css_payload__=\(cssLiteral);
        \(honestPath);
        \(pwaModeJs)
        """
    }

    static func load() -> InjectedScripts {
        InjectedScripts(
            honestPath: readResource("honest-path", ext: "js"),
            pwaModeJs: readResource("pwa-mode", ext: "js"),
            pwaModeCss: readResource("pwa-mode", ext: "css"),
            sdkStub: readResource("ya-sdk-stub", ext: "js")
        )
    }

    private static func readResource(_ name: String, ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            assertionFailure("Missing bundle resource \(name).\(ext)")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func jsString(_ value: String) -> String {
        var out = "\""
        for char in value.unicodeScalars {
            switch char.value {
            case 0x5C: out.append("\\\\")
            case 0x22: out.append("\\\"")
            case 0x0A: out.append("\\n")
            case 0x0D: out.append("\\r")
            case 0x09: out.append("\\t")
            case 0x2028: out.append("\\u2028")
            case 0x2029: out.append("\\u2029")
            default: out.append(Character(char))
            }
        }
        out.append("\"")
        return out
    }
}
