import Foundation

/// A `Speaker` that discards everything. Used for `--mute` (passthrough) mode
/// and as a convenient stand-in for tests.
public final class NullSpeaker: Speaker {
    public init() {}
    public func speak(_ text: String) {}
    public func stop() {}
}
