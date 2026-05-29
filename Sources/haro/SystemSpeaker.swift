import Foundation
import HaroCore

#if os(macOS)
import AVFoundation

/// `Speaker` implementation backed by AVFoundation's speech synthesizer.
///
/// Phrases are spoken sequentially: `AVSpeechSynthesizer` already queues
/// utterances, so we simply enqueue each phrase and let it play in order.
public final class SystemSpeaker: NSObject, Speaker {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private let rate: Float
    private let volume: Float

    /// - Parameters:
    ///   - voiceIdentifier: An AVSpeechSynthesisVoice identifier or a BCP-47
    ///     language code (e.g. "zh-CN"). When `nil`, the system default is used.
    public init(voiceIdentifier: String?, rate: Float?, volume: Float?) {
        self.voice = SystemSpeaker.resolveVoice(voiceIdentifier)
        // AVSpeechUtteranceDefaultSpeechRate sits between min and max.
        self.rate = rate ?? AVSpeechUtteranceDefaultSpeechRate
        self.volume = volume ?? 1.0
        super.init()
    }

    public func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let voice = voice {
            utterance.voice = voice
        }
        utterance.rate = clamp(rate,
                               min: AVSpeechUtteranceMinimumSpeechRate,
                               max: AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = clamp(volume, min: 0.0, max: 1.0)
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func clamp(_ value: Float, min lower: Float, max upper: Float) -> Float {
        Swift.min(Swift.max(value, lower), upper)
    }

    /// Resolve a voice from either an exact identifier or a language code.
    private static func resolveVoice(_ identifier: String?) -> AVSpeechSynthesisVoice? {
        guard let identifier = identifier, !identifier.isEmpty else { return nil }

        // Exact identifier match first.
        if let exact = AVSpeechSynthesisVoice(identifier: identifier) {
            return exact
        }
        // Fall back to treating the value as a language code.
        if let byLanguage = AVSpeechSynthesisVoice(language: identifier) {
            return byLanguage
        }
        // Last resort: case-insensitive language prefix match across all voices.
        let lowered = identifier.lowercased()
        return AVSpeechSynthesisVoice.speechVoices().first {
            $0.language.lowercased().hasPrefix(lowered)
        }
    }
}
#endif
