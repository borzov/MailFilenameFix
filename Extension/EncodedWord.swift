import Foundation

/// RFC 2047 encoded-words ("=?utf-8?B?0J8=?=") plus the charset lookup shared
/// with the RFC 2231 parameter parser.
enum EncodedWord {

    private static let wordRegex = try! NSRegularExpression(
        pattern: "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=",
        options: []
    )

    /// Decodes every encoded-word in `s`. Returns nil when there is none, so
    /// callers can tell "nothing to decode" from "decoded to the same text".
    static func decode(_ s: String) -> String? {
        let ns = s as NSString
        let matches = wordRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        var out = ""
        var cursor = 0
        var previousWasWord = false
        for m in matches {
            let gap = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            // RFC 2047: whitespace between two adjacent encoded-words is separator, not content
            if !(previousWasWord && gap.trimmingCharacters(in: .whitespaces).isEmpty) {
                out += gap
            }
            let charset = ns.substring(with: m.range(at: 1))
            let kind = ns.substring(with: m.range(at: 2)).lowercased()
            let payload = ns.substring(with: m.range(at: 3))
            guard let bytes = kind == "b" ? base64Decode(payload) : qDecode(payload),
                  let text = String(data: bytes, encoding: encoding(for: charset))
                    ?? String(data: bytes, encoding: .isoLatin1) else {
                // undecodable word: keep it verbatim rather than dropping the name
                out += ns.substring(with: m.range)
                cursor = m.range.location + m.range.length
                previousWasWord = false
                continue
            }
            out += text
            cursor = m.range.location + m.range.length
            previousWasWord = true
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// The form Mail.app renders correctly.
    static func encode(_ text: String) -> String {
        "=?utf-8?B?" + Data(text.utf8).base64EncodedString() + "?="
    }

    static func encoding(for charset: String) -> String.Encoding {
        switch charset.lowercased() {
        case "utf-8", "utf8", "": return .utf8
        case "windows-1251", "cp1251": return .windowsCP1251
        case "koi8-r":
            let cf = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.KOI8_R.rawValue))
            return String.Encoding(rawValue: cf)
        case "iso-8859-1", "latin-1", "latin1": return .isoLatin1
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cf != kCFStringEncodingInvalidId {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            }
            return .utf8
        }
    }

    // MARK: - payload decoding

    private static func base64Decode(_ s: String) -> Data? {
        let compact = s.replacingOccurrences(of: " ", with: "")
        // senders sometimes drop the padding
        let padding = (4 - compact.count % 4) % 4
        return Data(base64Encoded: compact + String(repeating: "=", count: padding))
    }

    private static func qDecode(_ s: String) -> Data? {
        var out = Data()
        var iter = s.makeIterator()
        while let ch = iter.next() {
            switch ch {
            case "_":
                out.append(0x20)
            case "=":
                guard let h1 = iter.next(), let h2 = iter.next(),
                      let byte = UInt8(String([h1, h2]), radix: 16) else { return nil }
                out.append(byte)
            default:
                guard let bytes = String(ch).data(using: .isoLatin1) else { return nil }
                out.append(bytes)
            }
        }
        return out
    }
}
