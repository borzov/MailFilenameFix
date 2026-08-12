import Foundation

/// Fixes attachment names in Content-Disposition and Content-Type headers,
/// rewriting them into the RFC 2047 encoded-word form Mail.app renders
/// correctly (filename="=?utf-8?B?...?="). Two defects are handled:
///
///  - RFC 2231/5987 extended parameters (filename*=utf-8''%D0%93..., including
///    filename*0*/filename*1* continuations), which Mail shows verbatim;
///  - mojibake ("Ð¸Ð·Ð¾Ð±ÑÐ°Ð¶ÐµÐ½Ð¸Ðµ.png"), whether the header carries raw
///    UTF-8 bytes, an encoded-word around already-broken text, or a charset
///    that lies about its contents. See MojibakeRepair.
///
/// The transformation is byte-surgical: only affected header lines change,
/// the rest of the message is preserved byte-for-byte.
enum FilenameFixer {

    /// Full header block: name + value with folded continuation lines.
    private static let headerRegex = try! NSRegularExpression(
        pattern: "^(Content-(?:Disposition|Type)[ \\t]*:)((?:[^\\r\\n]*)(?:\\r?\\n[ \\t][^\\r\\n]*)*)",
        options: [.caseInsensitive, .anchorsMatchLines]
    )
    /// A single parameter key: filename, filename*, filename*0, filename*1*, name...
    private static let keyRegex = try! NSRegularExpression(
        pattern: "^((?:file)?name)(?:\\*(\\d+))?(\\*)?$",
        options: [.caseInsensitive]
    )

    /// Returns fixed RFC822 data, or nil if the message needs no fix.
    static func fix(_ data: Data) -> Data? {
        // lossless byte <-> character mapping
        guard let text = String(data: data, encoding: .isoLatin1) else { return nil }
        // cheap pre-check before running the header regex: a name can only be
        // broken as an extended parameter, inside an encoded-word, or as
        // 8-bit bytes sitting raw in the header
        guard text.range(of: "name*", options: .caseInsensitive) != nil
                || text.range(of: "=?") != nil
                || text.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return nil }
        // never touch cryptographically signed mail
        let head = String(text.prefix(8192))
        if head.range(of: "multipart/signed", options: .caseInsensitive) != nil { return nil }

        let ns = text as NSString
        var result = ""
        var cursor = 0
        var changed = false
        let matches = headerRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let name = ns.substring(with: m.range(at: 1))
            let value = ns.substring(with: m.range(at: 2))
            guard let rebuilt = rebuildHeaderValue(name: name, value: value) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            result += name + " " + rebuilt
            cursor = m.range.location + m.range.length
            changed = true
        }
        guard changed else { return nil }
        result += ns.substring(from: cursor)
        return result.data(using: .isoLatin1)
    }

    // MARK: - header value parsing

    private struct Param {
        let key: String
        let value: String
    }

    /// Splits a header value on ';' honoring quoted strings.
    private static func splitParams(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var previous: Character = " "
        for ch in value {
            if ch == "\"" && previous != "\\" { inQuotes.toggle() }
            if ch == ";" && !inQuotes {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            previous = ch
        }
        parts.append(current)
        return parts
    }

    private static func unfold(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func unquote(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
            v = String(v.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return v
    }

    private static func percentDecode(_ s: String) -> Data {
        var out = Data()
        var iter = s.makeIterator()
        while let ch = iter.next() {
            if ch == "%", let h1 = iter.next(), let h2 = iter.next(),
               let byte = UInt8(String([h1, h2]), radix: 16) {
                out.append(byte)
            } else {
                out.append(contentsOf: String(ch).data(using: .isoLatin1) ?? Data())
            }
        }
        return out
    }

    /// Decodes a plain filename parameter and repairs it if it is mojibake.
    /// Returns nil when the name is already displayed correctly by Mail.
    private static func repairedName(_ raw: String) -> String? {
        MojibakeRepair.repair(EncodedWord.decode(raw) ?? raw)
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Rebuilds a header value, converting extended filename/name params
    /// to RFC 2047. Returns nil if nothing needed converting.
    private static func rebuildHeaderValue(name: String, value: String) -> String? {
        let flat = unfold(value)
        let rawParts = splitParams(flat)
        guard rawParts.count > 1 else { return nil }
        let mainValue = rawParts[0].trimmingCharacters(in: .whitespaces)

        // segments of extended names, keyed by base param name
        struct Segment { let index: Int; let extended: Bool; let raw: String }
        var segments: [String: [Segment]] = [:]
        var charsets: [String: String] = [:]
        var plain: [Param] = []
        var others: [Param] = []
        var order: [String] = []

        for part in rawParts.dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else {
                if !trimmed.isEmpty { others.append(Param(key: trimmed, value: "")) }
                continue
            }
            let rawKey = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: eq)...])
            let lower = rawKey.lowercased()
            let lowerNS = lower as NSString
            let keyMatch = keyRegex.firstMatch(
                in: lower, range: NSRange(location: 0, length: lowerNS.length))
            // only extended/continuation forms (with '*') are our business
            if let m = keyMatch,
               m.range(at: 2).location != NSNotFound || m.range(at: 3).location != NSNotFound {
                let base = lowerNS.substring(with: m.range(at: 1))
                let index = m.range(at: 2).location != NSNotFound
                    ? Int(lowerNS.substring(with: m.range(at: 2))) ?? 0 : 0
                let extended = m.range(at: 3).location != NSNotFound
                var payload = unquote(rawValue)
                if extended && index == 0 {
                    // charset'lang'data
                    let pieces = payload.split(separator: "'", maxSplits: 2,
                                               omittingEmptySubsequences: false)
                    if pieces.count == 3 {
                        charsets[base] = String(pieces[0])
                        payload = String(pieces[2])
                    }
                }
                if segments[base] == nil { order.append(base) }
                segments[base, default: []].append(
                    Segment(index: index, extended: extended, raw: payload))
            } else if keyMatch != nil {
                // plain filename=/name= — may still carry a broken name
                plain.append(Param(key: lower, value: unquote(rawValue)))
            } else {
                others.append(Param(key: rawKey, value: unquote(rawValue)))
            }
        }
        guard !segments.isEmpty || !plain.isEmpty else { return nil }

        var rebuilt: [String] = [mainValue]
        for p in others {
            rebuilt.append(p.value.isEmpty ? p.key : "\(p.key)=\(quoted(p.value))")
        }
        var converted = false
        for p in plain {
            guard let repaired = repairedName(p.value) else {
                rebuilt.append("\(p.key)=\(quoted(p.value))")
                continue
            }
            rebuilt.append("\(p.key)=\(quoted(EncodedWord.encode(repaired)))")
            converted = true
        }
        for base in order {
            guard let segs = segments[base]?.sorted(by: { $0.index < $1.index }) else { continue }
            var bytes = Data()
            for seg in segs {
                if seg.extended {
                    bytes.append(percentDecode(seg.raw))
                } else {
                    bytes.append(seg.raw.data(using: .isoLatin1) ?? Data())
                }
            }
            let encoding = EncodedWord.encoding(for: charsets[base] ?? "utf-8")
            guard var decoded = String(data: bytes, encoding: encoding)
                    ?? String(data: bytes, encoding: .isoLatin1) else { continue }
            // the charset may have lied — bytes declared latin-1 are often UTF-8
            if let repaired = MojibakeRepair.repair(decoded) { decoded = repaired }
            decoded = decoded.replacingOccurrences(of: "/", with: ":")
                .trimmingCharacters(in: .whitespaces)
            guard !decoded.isEmpty else { continue }
            let paramValue = decoded.allSatisfy { $0.isASCII }
                ? quoted(decoded) : quoted(EncodedWord.encode(decoded))
            rebuilt.append("\(base)=\(paramValue)")
            converted = true
        }
        guard converted else { return nil }
        return rebuilt.joined(separator: "; ")
    }
}
