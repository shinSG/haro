import Foundation
import HaroCore

#if os(macOS)

/// `Speaker` implementation that synthesizes speech using a configurable
/// third-party HTTP TTS service and plays the returned audio with `afplay`.
///
/// Requests and playback run on a private serial queue so phrases are spoken in
/// order and the caller (the PTY I/O loop) is never blocked.
public final class RemoteTTSSpeaker: Speaker {
    private let provider: TTSProviderConfig
    private let environment: [String: String]
    private let session: URLSession
    private let queue = DispatchQueue(label: "haro.remote-tts")

    /// Tracks the currently playing `afplay` process so `stop()` can cancel it.
    private let lock = NSLock()
    private var currentPlayer: Process?
    private var stopped = false

    public init(provider: TTSProviderConfig, environment: [String: String]) {
        self.provider = provider
        self.environment = environment
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = provider.timeout
        configuration.timeoutIntervalForResource = provider.timeout
        self.session = URLSession(configuration: configuration)
    }

    public func speak(_ text: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); let isStopped = self.stopped; self.lock.unlock()
            if isStopped { return }
            self.synthesizeAndPlay(text)
        }
    }

    public func stop() {
        lock.lock()
        stopped = true
        let player = currentPlayer
        lock.unlock()
        player?.terminate()
    }

    // MARK: - Pipeline

    private func synthesizeAndPlay(_ text: String) {
        guard let audio = fetchAudio(for: text) else { return }
        playAudio(audio, format: provider.format)
    }

    /// Perform the (synchronous) HTTP request and extract audio bytes.
    private func fetchAudio(for text: String) -> Data? {
        let ttsRequest = provider.buildRequest(text: text, environment: environment)
        guard let url = URL(string: ttsRequest.url) else {
            warn("invalid provider URL '\(ttsRequest.url)'")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = ttsRequest.method
        request.httpBody = ttsRequest.body
        for (key, value) in ttsRequest.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = resultError {
            warn("TTS request failed: \(error.localizedDescription)")
            return nil
        }
        if let http = resultResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            warn("TTS service returned HTTP \(http.statusCode)")
            return nil
        }
        guard let data = resultData, !data.isEmpty else {
            warn("TTS service returned no audio")
            return nil
        }

        if let field = provider.audioBase64Field {
            return decodeBase64Audio(from: data, keyPath: field)
        }
        return data
    }

    /// Extract base64-encoded audio from a JSON response at a dotted key path.
    private func decodeBase64Audio(from data: Data, keyPath: String) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            warn("could not parse JSON response for audioBase64Field")
            return nil
        }
        var node: Any? = object
        for component in keyPath.split(separator: ".") {
            guard let dict = node as? [String: Any] else { node = nil; break }
            node = dict[String(component)]
        }
        guard let base64 = node as? String,
              let audio = Data(base64Encoded: base64) else {
            warn("audioBase64Field '\(keyPath)' not found or not base64")
            return nil
        }
        return audio
    }

    /// Write audio to a temp file and play it synchronously via `afplay`.
    private func playAudio(_ audio: Data, format: String) {
        let ext = format.isEmpty ? "mp3" : format
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haro-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try audio.write(to: tempURL)
        } catch {
            warn("could not write temp audio file: \(error.localizedDescription)")
            return
        }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [tempURL.path]

        lock.lock()
        if stopped { lock.unlock(); return }
        currentPlayer = player
        lock.unlock()

        do {
            try player.run()
            player.waitUntilExit()
        } catch {
            warn("could not play audio with afplay: \(error.localizedDescription)")
        }

        lock.lock()
        currentPlayer = nil
        lock.unlock()
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(Data("haro: \(message)\n".utf8))
    }
}
#endif
