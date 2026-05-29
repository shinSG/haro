import Foundation

/// Lightweight string templating used to build third-party TTS API requests.
///
/// Two placeholder kinds are supported:
/// - `{{name}}` is replaced from a caller-supplied `values` map (e.g. the text
///   to synthesize, the selected voice, the audio format).
/// - `${NAME}` is replaced from the process environment, which is the
///   recommended way to inject secrets such as API keys without writing them
///   into a config file.
///
/// Unknown placeholders expand to an empty string so a partially configured
/// template fails loudly at the API instead of leaking literal `{{...}}`.
public enum Template {
    /// Render `template`, expanding `{{...}}` from `values` and `${...}` from
    /// `environment`.
    public static func render(_ template: String,
                              values: [String: String],
                              environment: [String: String]) -> String {
        let scalars = Array(template.unicodeScalars)
        let count = scalars.count
        var result = String.UnicodeScalarView()
        result.reserveCapacity(count)

        var i = 0
        while i < count {
            let scalar = scalars[i]

            // {{ name }}
            if scalar == "{", i + 1 < count, scalars[i + 1] == "{" {
                if let close = indexOfClose(scalars, from: i + 2, marker: "}", needsDouble: true) {
                    let name = name(in: scalars, from: i + 2, to: close)
                    result.append(contentsOf: (values[name] ?? "").unicodeScalars)
                    i = close + 2
                    continue
                }
            }

            // ${ NAME }
            if scalar == "$", i + 1 < count, scalars[i + 1] == "{" {
                if let close = indexOfClose(scalars, from: i + 2, marker: "}", needsDouble: false) {
                    let name = name(in: scalars, from: i + 2, to: close)
                    result.append(contentsOf: (environment[name] ?? "").unicodeScalars)
                    i = close + 1
                    continue
                }
            }

            result.append(scalar)
            i += 1
        }

        return String(result)
    }

    /// JSON-escape a string for safe interpolation inside a JSON string literal
    /// in a body template (the caller writes `"input": "{{text}}"`).
    public static func jsonEscape(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out.append(contentsOf: "\\\"".unicodeScalars)
            case "\\": out.append(contentsOf: "\\\\".unicodeScalars)
            case "\n": out.append(contentsOf: "\\n".unicodeScalars)
            case "\r": out.append(contentsOf: "\\r".unicodeScalars)
            case "\t": out.append(contentsOf: "\\t".unicodeScalars)
            default:
                if scalar.value < 0x20 {
                    let hex = String(format: "\\u%04x", scalar.value)
                    out.append(contentsOf: hex.unicodeScalars)
                } else {
                    out.append(scalar)
                }
            }
        }
        return String(out)
    }

    // MARK: - Helpers

    /// Find the index of the closing marker starting at `from`. When
    /// `needsDouble` is true, the closer is two consecutive `marker` scalars
    /// (for `}}`) and the returned index points at the first one.
    private static func indexOfClose(_ scalars: [Unicode.Scalar],
                                     from: Int,
                                     marker: Unicode.Scalar,
                                     needsDouble: Bool) -> Int? {
        var j = from
        let count = scalars.count
        while j < count {
            if scalars[j] == marker {
                if needsDouble {
                    if j + 1 < count && scalars[j + 1] == marker { return j }
                } else {
                    return j
                }
            }
            j += 1
        }
        return nil
    }

    private static func name(in scalars: [Unicode.Scalar], from: Int, to: Int) -> String {
        let slice = String(String.UnicodeScalarView(scalars[from..<to]))
        return slice.trimmingCharacters(in: .whitespaces)
    }
}
