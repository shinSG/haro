import Foundation

/// Decides whether a line of cleaned terminal text is worth speaking and, if
/// so, normalizes it into a concise phrase.
///
/// Claude Code renders a rich TUI (spinners, box-drawing frames, progress
/// counters, prompts). Speaking all of it would be noise, so this filter keeps
/// only lines that carry real prose and collapses decorative characters.
public struct LineFilter {
    /// Minimum number of "meaningful" characters (letters/digits/CJK) a line
    /// must contain to be spoken.
    public var minMeaningfulCharacters: Int

    public init(minMeaningfulCharacters: Int = 2) {
        self.minMeaningfulCharacters = minMeaningfulCharacters
    }

    /// Characters used purely for TUI decoration that should be dropped from
    /// the spoken phrase.
    private static let decorativeScalars: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        // Box drawing (U+2500...U+257F) and block elements (U+2580...U+259F).
        for value in 0x2500...0x259F { if let s = Unicode.Scalar(value) { set.insert(s) } }
        // Common bullet / spinner / status glyphs.
        for value in [0x2022, 0x25CF, 0x25CB, 0x25AA, 0x25A0, 0x2713, 0x2714,
                      0x2717, 0x2718, 0x2026, 0x2588, 0x2502, 0x2014, 0x2013,
                      0x00B7, 0x2219, 0x276F, 0x203A, 0x2192, 0x2190] {
            if let s = Unicode.Scalar(value) { set.insert(s) }
        }
        // Braille spinner frames (U+2800...U+28FF).
        for value in 0x2800...0x28FF { if let s = Unicode.Scalar(value) { set.insert(s) } }
        return set
    }()

    /// Returns a normalized phrase to speak, or `nil` if the line is noise.
    public func phrase(for rawLine: String) -> String? {
        // Drop decorative scalars, then collapse whitespace.
        var scalars = String.UnicodeScalarView()
        for scalar in rawLine.unicodeScalars where !Self.decorativeScalars.contains(scalar) {
            scalars.append(scalar)
        }
        let cleaned = collapseWhitespace(String(scalars))
        if cleaned.isEmpty { return nil }

        // Require a minimum amount of real content.
        if meaningfulCount(in: cleaned) < minMeaningfulCharacters { return nil }

        return cleaned
    }

    private func collapseWhitespace(_ text: String) -> String {
        let components = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return components.joined(separator: " ")
    }

    private func meaningfulCount(in text: String) -> Int {
        var count = 0
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || isCJK(scalar) {
                count += 1
            }
        }
        return count
    }

    private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,    // CJK Unified Ideographs
             0x3040...0x30FF,    // Hiragana + Katakana
             0xAC00...0xD7AF:    // Hangul syllables
            return true
        default:
            return false
        }
    }
}
