import Foundation

/// A fully resolved HTTP request to send to a third-party TTS service.
public struct TTSRequest: Equatable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: Data

    public init(url: String, method: String, headers: [String: String], body: Data) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// Describes how `haro` should talk to a configurable third-party TTS API.
///
/// The shape is deliberately vendor-agnostic: any HTTP service that accepts a
/// piece of text and returns synthesized audio can be configured by supplying a
/// URL, headers, and a request-body template. This is loaded from a JSON config
/// file (see `--config`). Example for an OpenAI-compatible endpoint:
///
/// ```json
/// {
///   "url": "https://api.openai.com/v1/audio/speech",
///   "method": "POST",
///   "headers": {
///     "Authorization": "******",
///     "Content-Type": "application/json"
///   },
///   "body": "{\"model\":\"tts-1\",\"voice\":\"{{voice}}\",\"input\":\"{{text}}\",\"response_format\":\"{{format}}\"}",
///   "voice": "alloy",
///   "format": "mp3"
/// }
/// ```
public struct TTSProviderConfig: Codable, Equatable {
    /// Endpoint URL. May contain `${ENV}` placeholders.
    public var url: String
    /// HTTP method. Defaults to `POST`.
    public var method: String
    /// HTTP headers. Values may contain `${ENV}` (e.g. for API keys) and `{{...}}`.
    public var headers: [String: String]
    /// Request body template. Use `{{text}}` (JSON-escaped), `{{voice}}`,
    /// `{{format}}`, `{{rate}}`, and `${ENV}` placeholders.
    public var body: String
    /// Voice/model identifier passed to the service via `{{voice}}`.
    public var voice: String?
    /// Audio format requested and used as the playback file extension
    /// (e.g. `mp3`, `wav`, `aac`). Defaults to `mp3`.
    public var format: String
    /// Optional speaking rate exposed to the template via `{{rate}}`.
    public var rate: Double?
    /// If set, the response is treated as JSON and the audio bytes are read as
    /// base64 from this (optionally dotted) key path, e.g. `audioContent` or
    /// `data.audio`. If `nil`, the raw response body is treated as audio.
    public var audioBase64Field: String?
    /// Request timeout in seconds. Defaults to 30.
    public var timeout: Double

    public init(url: String,
                method: String = "POST",
                headers: [String: String] = [:],
                body: String,
                voice: String? = nil,
                format: String = "mp3",
                rate: Double? = nil,
                audioBase64Field: String? = nil,
                timeout: Double = 30) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.voice = voice
        self.format = format
        self.rate = rate
        self.audioBase64Field = audioBase64Field
        self.timeout = timeout
    }

    private enum CodingKeys: String, CodingKey {
        case url, method, headers, body, voice, format, rate, audioBase64Field, timeout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? "POST"
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        body = try c.decode(String.self, forKey: .body)
        voice = try c.decodeIfPresent(String.self, forKey: .voice)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "mp3"
        rate = try c.decodeIfPresent(Double.self, forKey: .rate)
        audioBase64Field = try c.decodeIfPresent(String.self, forKey: .audioBase64Field)
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 30
    }

    /// Build the concrete HTTP request for a given phrase, expanding all
    /// placeholders using `environment` (typically the process environment).
    public func buildRequest(text: String, environment: [String: String]) -> TTSRequest {
        let values: [String: String] = [
            "text": Template.jsonEscape(text),
            "voice": Template.jsonEscape(voice ?? ""),
            "format": Template.jsonEscape(format),
            "rate": rate.map { String($0) } ?? ""
        ]

        let renderedURL = Template.render(url, values: values, environment: environment)
        let renderedBody = Template.render(body, values: values, environment: environment)

        var renderedHeaders: [String: String] = [:]
        for (key, value) in headers {
            renderedHeaders[key] = Template.render(value, values: values, environment: environment)
        }

        return TTSRequest(url: renderedURL,
                          method: method,
                          headers: renderedHeaders,
                          body: Data(renderedBody.utf8))
    }
}
