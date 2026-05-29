import Foundation

/// Removes ANSI/VT100 escape sequences and most control characters from text
/// captured from a terminal, leaving human-readable content suitable for TTS.
///
/// The stripper is intentionally stateful: terminal output arrives in arbitrary
/// chunks, and an escape sequence may be split across two reads. Feeding text
/// through a single `ANSIStripper` instance preserves the parser state between
/// calls so partial sequences are handled correctly.
public final class ANSIStripper {
    private enum State {
        case normal
        case escape          // saw ESC, waiting for the next byte
        case csi             // ESC [ ... terminated by a byte in 0x40...0x7E
        case osc             // ESC ] ... terminated by BEL or ESC \
        case oscEscape       // inside OSC, saw ESC, expecting '\'
    }

    private var state: State = .normal

    public init() {}

    /// Feed a chunk of raw terminal text and return the cleaned text.
    public func feed(_ input: String) -> String {
        var output = String.UnicodeScalarView()
        output.reserveCapacity(input.unicodeScalars.count)

        for scalar in input.unicodeScalars {
            switch state {
            case .normal:
                if scalar == "\u{1B}" {
                    state = .escape
                } else if isStrippableControl(scalar) {
                    // Drop control characters such as BEL, VT, FF, NUL.
                    continue
                } else {
                    output.append(scalar)
                }

            case .escape:
                switch scalar {
                case "[":
                    state = .csi
                case "]":
                    state = .osc
                case "P", "X", "^", "_":
                    // DCS / SOS / PM / APC strings: treat like OSC (string terminator).
                    state = .osc
                default:
                    // Two-character escape (e.g. ESC c, ESC (B). Drop the final byte.
                    state = .normal
                }

            case .csi:
                // CSI parameters/intermediates are 0x20...0x3F; final byte 0x40...0x7E.
                if (0x40...0x7E).contains(scalar.value) {
                    state = .normal
                }

            case .osc:
                if scalar == "\u{07}" {            // BEL terminates the string.
                    state = .normal
                } else if scalar == "\u{1B}" {     // ESC may begin a String Terminator.
                    state = .oscEscape
                }

            case .oscEscape:
                // ESC \ is the String Terminator; any other byte stays in the string.
                state = (scalar == "\\") ? .normal : .osc
            }
        }

        return String(output)
    }

    private func isStrippableControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D:   // keep TAB, LF, CR for downstream line handling
            return false
        case 0x00...0x1F, 0x7F:  // other C0 controls + DEL
            return true
        default:
            return false
        }
    }
}
