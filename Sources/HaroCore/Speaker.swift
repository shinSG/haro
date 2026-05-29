import Foundation

/// Abstraction over a text-to-speech backend so the output pipeline can be
/// unit-tested without depending on AVFoundation / macOS.
public protocol Speaker: AnyObject {
    /// Enqueue a phrase to be spoken. Implementations should speak phrases
    /// sequentially in the order received.
    func speak(_ text: String)

    /// Stop any in-progress and queued speech.
    func stop()
}
