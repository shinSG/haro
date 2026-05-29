import Foundation

/// Pipeline that turns raw terminal output into spoken phrases:
/// raw chunk -> strip ANSI -> split into terminal lines (honoring carriage
/// returns used for in-place redraws) -> filter noise -> de-duplicate -> speak.
public final class OutputProcessor {
    private let stripper = ANSIStripper()
    private let filter: LineFilter
    private let speaker: Speaker

    /// The line currently being assembled (text since the last LF/CR).
    private var current = ""
    /// Recently spoken phrases, used to suppress duplicates caused by TUI redraws.
    private var recent: [String] = []
    private let recentCapacity = 12

    public init(speaker: Speaker, filter: LineFilter = LineFilter()) {
        self.speaker = speaker
        self.filter = filter
    }

    /// Feed a raw chunk of terminal output.
    public func feed(_ rawChunk: String) {
        let cleaned = stripper.feed(rawChunk)
        for scalar in cleaned.unicodeScalars {
            switch scalar {
            case "\n":
                finalizeCurrentLine()
            case "\r":
                // Carriage return rewinds the cursor; the line is redrawn in
                // place, so discard whatever was accumulated for it.
                current.removeAll(keepingCapacity: true)
            default:
                current.unicodeScalars.append(scalar)
            }
        }
    }

    /// Emit any text buffered for the final, unterminated line.
    public func flush() {
        finalizeCurrentLine()
    }

    private func finalizeCurrentLine() {
        let line = current
        current.removeAll(keepingCapacity: true)

        guard let phrase = filter.phrase(for: line) else { return }
        guard !recent.contains(phrase) else { return }

        recent.append(phrase)
        if recent.count > recentCapacity {
            recent.removeFirst(recent.count - recentCapacity)
        }

        speaker.speak(phrase)
    }
}
