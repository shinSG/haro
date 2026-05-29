import Foundation
import HaroCore

let rawArguments = Array(CommandLine.arguments.dropFirst())

let config: Configuration
do {
    config = try Configuration.parse(rawArguments)
} catch {
    FileHandle.standardError.write(Data("haro: \(error)\n\n".utf8))
    FileHandle.standardError.write(Data((Configuration.usage + "\n").utf8))
    exit(64) // EX_USAGE
}

if config.showHelp {
    print(Configuration.usage)
    exit(0)
}

#if os(macOS)
func makeSpeaker(_ config: Configuration) -> Speaker {
    if config.mute {
        return NullSpeaker()
    }

    switch config.engine {
    case .system:
        return SystemSpeaker(voiceIdentifier: config.voice, rate: config.rate, volume: config.volume)
    case .api:
        do {
            guard let provider = try config.resolveProvider(load: {
                try Data(contentsOf: URL(fileURLWithPath: $0))
            }) else {
                // Should not happen for .api, but fall back safely.
                return SystemSpeaker(voiceIdentifier: config.voice, rate: config.rate, volume: config.volume)
            }
            var environment = ProcessInfo.processInfo.environment
            if let apiKey = config.apiKey {
                environment["HARO_API_KEY"] = apiKey
            }
            return RemoteTTSSpeaker(provider: provider, environment: environment)
        } catch {
            FileHandle.standardError.write(Data("haro: \(error)\n".utf8))
            exit(78) // EX_CONFIG
        }
    }
}

let speaker = makeSpeaker(config)
let filter = LineFilter(minMeaningfulCharacters: config.minMeaningfulCharacters)
let processor = OutputProcessor(speaker: speaker, filter: filter)
let runner = PTYRunner(processor: processor)

let status = runner.run(command: config.command)
exit(status)
#else
FileHandle.standardError.write(Data(
    "haro requires macOS: it relies on a pseudo-terminal and the system speech synthesizer.\n".utf8))
exit(1)
#endif
