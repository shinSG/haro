import Foundation

/// Which text-to-speech backend `haro` should use.
public enum TTSEngine: String, Equatable {
    /// Local macOS speech synthesizer (AVFoundation).
    case system
    /// A configurable third-party HTTP TTS service (see `TTSProviderConfig`).
    case api
}

/// Parsed command-line configuration for the `haro` wrapper.
public struct Configuration {
    /// The command (and its arguments) to launch and listen to.
    /// Defaults to running the `claude` CLI.
    public var command: [String]
    /// AVSpeechSynthesisVoice identifier or BCP-47 language code (e.g. "zh-CN").
    public var voice: String?
    /// Speaking rate in the 0.0...1.0 range used by AVSpeechUtterance.
    public var rate: Float?
    /// Volume in the 0.0...1.0 range.
    public var volume: Float?
    /// Minimum meaningful characters a line needs before it is spoken.
    public var minMeaningfulCharacters: Int
    /// When true, output is forwarded to the terminal but never spoken.
    public var mute: Bool
    /// When true, only `--help` was requested.
    public var showHelp: Bool
    /// Selected text-to-speech backend. Defaults to the local system engine.
    public var engine: TTSEngine
    /// Path to a JSON file describing the third-party TTS provider (`--config`).
    public var configPath: String?
    /// CLI override for the provider endpoint URL.
    public var apiURL: String?
    /// CLI override for the provider voice/model identifier.
    public var apiVoice: String?
    /// API key supplied on the command line. When set it is exposed to provider
    /// templates as the `HARO_API_KEY` environment variable so secrets can be
    /// referenced via `${HARO_API_KEY}` without writing them into a file.
    public var apiKey: String?

    public init(command: [String] = ["claude"],
                voice: String? = nil,
                rate: Float? = nil,
                volume: Float? = nil,
                minMeaningfulCharacters: Int = 2,
                mute: Bool = false,
                showHelp: Bool = false,
                engine: TTSEngine = .system,
                configPath: String? = nil,
                apiURL: String? = nil,
                apiVoice: String? = nil,
                apiKey: String? = nil) {
        self.command = command
        self.voice = voice
        self.rate = rate
        self.volume = volume
        self.minMeaningfulCharacters = minMeaningfulCharacters
        self.mute = mute
        self.showHelp = showHelp
        self.engine = engine
        self.configPath = configPath
        self.apiURL = apiURL
        self.apiVoice = apiVoice
        self.apiKey = apiKey
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case invalidValue(option: String, value: String)

        public var description: String {
            switch self {
            case .missingValue(let option):
                return "Missing value for option \(option)"
            case .invalidValue(let option, let value):
                return "Invalid value '\(value)' for option \(option)"
            }
        }
    }

    /// Errors raised while turning the parsed configuration into a concrete
    /// third-party TTS provider (loading/validating the config file).
    public enum ResolutionError: Error, CustomStringConvertible {
        case missingConfigFile
        case loadFailed(path: String, underlying: String)
        case decodeFailed(path: String, underlying: String)

        public var description: String {
            switch self {
            case .missingConfigFile:
                return "The 'api' engine requires a provider config file. Pass --config <file> "
                    + "(or use --engine system)."
            case .loadFailed(let path, let underlying):
                return "Could not read provider config '\(path)': \(underlying)"
            case .decodeFailed(let path, let underlying):
                return "Could not parse provider config '\(path)': \(underlying)"
            }
        }
    }

    /// Resolve the third-party TTS provider for the `api` engine.
    ///
    /// File access is injected via `load` so this stays pure and testable. For
    /// the `system` engine this returns `nil`. CLI overrides (`--api-url`,
    /// `--api-voice`) are applied on top of the loaded config.
    public func resolveProvider(load: (String) throws -> Data) throws -> TTSProviderConfig? {
        guard engine == .api else { return nil }
        guard let path = configPath else { throw ResolutionError.missingConfigFile }

        let data: Data
        do {
            data = try load(path)
        } catch {
            throw ResolutionError.loadFailed(path: path, underlying: "\(error)")
        }

        var provider: TTSProviderConfig
        do {
            provider = try JSONDecoder().decode(TTSProviderConfig.self, from: data)
        } catch {
            throw ResolutionError.decodeFailed(path: path, underlying: "\(error)")
        }

        if let apiURL = apiURL { provider.url = apiURL }
        if let apiVoice = apiVoice { provider.voice = apiVoice }
        return provider
    }

    /// Parse arguments (excluding the program name).
    ///
    /// Recognized options are consumed until the first `--` or the first
    /// non-option token, after which the remaining tokens form the command to
    /// run. This lets users write: `haro --voice zh-CN -- claude --resume`.
    public static func parse(_ arguments: [String]) throws -> Configuration {
        var config = Configuration(command: [])
        var index = 0

        func nextValue(for option: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw ParseError.missingValue(option) }
            return arguments[index]
        }

        var sawTerminator = false

        while index < arguments.count {
            let arg = arguments[index]

            if sawTerminator {
                config.command.append(arg)
                index += 1
                continue
            }

            switch arg {
            case "-h", "--help":
                config.showHelp = true
            case "--":
                sawTerminator = true
            case "--voice":
                config.voice = try nextValue(for: arg)
            case "--rate":
                let raw = try nextValue(for: arg)
                guard let value = Float(raw) else {
                    throw ParseError.invalidValue(option: arg, value: raw)
                }
                config.rate = value
            case "--volume":
                let raw = try nextValue(for: arg)
                guard let value = Float(raw) else {
                    throw ParseError.invalidValue(option: arg, value: raw)
                }
                config.volume = value
            case "--min-length":
                let raw = try nextValue(for: arg)
                guard let value = Int(raw), value >= 0 else {
                    throw ParseError.invalidValue(option: arg, value: raw)
                }
                config.minMeaningfulCharacters = value
            case "--mute":
                config.mute = true
            case "--engine":
                let raw = try nextValue(for: arg)
                guard let value = TTSEngine(rawValue: raw) else {
                    throw ParseError.invalidValue(option: arg, value: raw)
                }
                config.engine = value
            case "--config":
                config.configPath = try nextValue(for: arg)
            case "--api-url":
                config.apiURL = try nextValue(for: arg)
            case "--api-voice":
                config.apiVoice = try nextValue(for: arg)
            case "--api-key":
                config.apiKey = try nextValue(for: arg)
            default:
                // First non-option token begins the command to run.
                config.command.append(arg)
                sawTerminator = true
            }

            index += 1
        }

        if config.command.isEmpty {
            config.command = ["claude"]
        }
        // Supplying a provider config file implies the API engine unless the
        // user explicitly asked for a different engine.
        if config.configPath != nil && config.engine == .system {
            config.engine = .api
        }
        return config
    }

    public static let usage = """
    haro - speak Claude Code's terminal output aloud (macOS).

    USAGE:
        haro [options] [-- command ...]

    Launches the target command (default: `claude`) inside a pseudo-terminal,
    forwards your keyboard and the program's display transparently, and reads
    the program's textual output aloud using the system text-to-speech engine.

    OPTIONS:
        --engine <system|api>
                            TTS backend. `system` uses the local macOS voice;
                            `api` calls a configurable third-party service.
                            Defaults to `system` (or `api` when --config is set).
        --config <file>     JSON file describing the third-party TTS provider
                            (URL, headers, request body template, voice, format).
                            Implies `--engine api`.
        --api-url <url>     Override the provider endpoint URL from --config.
        --api-voice <id>    Override the provider voice/model from --config.
        --api-key <key>     Secret exposed to the provider config as the
                            ${HARO_API_KEY} environment variable.
        --voice <id|lang>   System engine: voice identifier or language code
                            (e.g. zh-CN, en-US, com.apple.voice...Samantha).
        --rate <0.0-1.0>    System engine: speaking rate (AVSpeechUtterance scale).
        --volume <0.0-1.0>  System engine: speaking volume.
        --min-length <n>    Minimum meaningful characters before a line is spoken
                            (default: 2). Higher values reduce chatter.
        --mute              Forward output without speaking (passthrough only).
        -h, --help          Show this help.

    EXAMPLES:
        haro
        haro --voice zh-CN --rate 0.5
        haro --engine api --config ~/.config/haro/openai.json --api-key sk-...
        haro --config ./elevenlabs.json -- claude --resume
        haro --voice en-US -- npm run some-cli
    """
}
