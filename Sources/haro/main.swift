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
let speaker: Speaker = config.mute
    ? NullSpeaker()
    : SystemSpeaker(voiceIdentifier: config.voice, rate: config.rate, volume: config.volume)

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
