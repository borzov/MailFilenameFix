import Foundation

/// Repairs "mojibake" — text whose UTF-8 bytes were once decoded as a
/// single-byte charset, turning "изображение" into "Ð¸Ð·Ð¾Ð±ÑÐ°Ð¶ÐµÐ½Ð¸Ðµ".
///
/// The detector is deterministic, not statistical: the string is mapped back
/// to the bytes it came from and decoded as strict UTF-8. Strict decoding
/// fails on anything that was not UTF-8 to begin with, so a genuine
/// "Résumé.pdf" is rejected instead of being mangled.
enum MojibakeRepair {

    /// Repairs `s`, or returns nil when it is not (or no longer) mojibake.
    static func repair(_ s: String) -> String? {
        var current = s
        var repaired: String? = nil
        // relays can encode the same name twice; three rounds is well past
        // anything seen in the wild and keeps the loop bounded
        for _ in 0..<3 {
            guard let next = repairOnce(current) else { break }
            repaired = next
            current = next
        }
        return repaired
    }

    // MARK: - single round

    private static func repairOnce(_ s: String) -> String? {
        // pure ASCII cannot be mojibake
        guard s.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return nil }
        guard let bytes = singleByteEncode(s), bytes.count >= 2 else { return nil }
        // strict: Swift returns nil for byte sequences that are not valid UTF-8
        guard let decoded = String(data: bytes, encoding: .utf8), decoded != s else { return nil }
        guard isPlausibleFilename(decoded) else { return nil }
        return decoded
    }

    /// Maps each scalar back to the byte it was decoded from, or nil if some
    /// scalar cannot come from a single byte — meaning this is not mojibake.
    private static func singleByteEncode(_ s: String) -> Data? {
        var out = Data()
        for scalar in s.unicodeScalars {
            if scalar.value <= 0xFF {
                out.append(UInt8(scalar.value))
            } else if let byte = cp1252Extras[scalar] {
                out.append(byte)
            } else {
                return nil
            }
        }
        return out
    }

    private static func isPlausibleFilename(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0..<0x20, 0x7F:        return false    // control characters
            case 0xFFFD:                return false    // replacement character
            case 0xE000...0xF8FF:       return false    // private use area
            case 0xFFFE, 0xFFFF:        return false    // non-characters
            default:                    continue
            }
        }
        return true
    }

    /// CP1252 fills 0x80–0x9F, where Latin-1 has control characters. A client
    /// decoding UTF-8 as CP1252 therefore produces these scalars, and they map
    /// back to exactly one byte each.
    private static let cp1252Extras: [Unicode.Scalar: UInt8] = [
        "\u{20AC}": 0x80, "\u{201A}": 0x82, "\u{0192}": 0x83, "\u{201E}": 0x84,
        "\u{2026}": 0x85, "\u{2020}": 0x86, "\u{2021}": 0x87, "\u{02C6}": 0x88,
        "\u{2030}": 0x89, "\u{0160}": 0x8A, "\u{2039}": 0x8B, "\u{0152}": 0x8C,
        "\u{017D}": 0x8E, "\u{2018}": 0x91, "\u{2019}": 0x92, "\u{201C}": 0x93,
        "\u{201D}": 0x94, "\u{2022}": 0x95, "\u{2013}": 0x96, "\u{2014}": 0x97,
        "\u{02DC}": 0x98, "\u{2122}": 0x99, "\u{0161}": 0x9A, "\u{203A}": 0x9B,
        "\u{0153}": 0x9C, "\u{017E}": 0x9E, "\u{0178}": 0x9F,
    ]
}
