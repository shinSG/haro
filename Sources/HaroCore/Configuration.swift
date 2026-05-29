import Foundation

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

    public init(command: [String] = ["claude"],
                voice: String? = nil,
                rate: Float? = nil,
                volume: Float? = nil,
                minMeaningfulCharacters: Int = 2,
                mute: Bool = false,
                showHelp: Bool = false) {
        self.command = command
        self.voice = voice
        self.rate = rate
        self.volume = volume
        self.minMeaningfulCharacters = minMeaningfulCharacters
        self.mute = mute
        self.showHelp = showHelp
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
        --voice <id|lang>   Voice identifier or language code (e.g. zh-CN, en-US,
                            or com.apple.voice.compact.en-US.Samantha).
        --rate <0.0-1.0>    Speaking rate (AVSpeechUtterance scale).
        --volume <0.0-1.0>  Speaking volume.
        --min-length <n>    Minimum meaningful characters before a line is spoken
                            (default: 2). Higher values reduce chatter.
        --mute              Forward output without speaking (passthrough only).
        -h, --help          Show this help.

    EXAMPLES:
        haro
        haro --voice zh-CN --rate 0.5
        haro -- claude --resume
        haro --voice en-US -- npm run some-cli
    """
}
