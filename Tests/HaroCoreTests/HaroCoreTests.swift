import XCTest
@testable import HaroCore

/// A test double that records spoken phrases.
final class RecordingSpeaker: Speaker {
    private(set) var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
}

final class ANSIStripperTests: XCTestCase {
    func testStripsColorSGRSequences() {
        let stripper = ANSIStripper()
        let input = "\u{1B}[31mHello\u{1B}[0m World"
        XCTAssertEqual(stripper.feed(input), "Hello World")
    }

    func testStripsCursorAndEraseSequences() {
        let stripper = ANSIStripper()
        let input = "\u{1B}[2K\u{1B}[1;1HText"
        XCTAssertEqual(stripper.feed(input), "Text")
    }

    func testStripsOSCTitleSequence() {
        let stripper = ANSIStripper()
        let bel = "\u{1B}]0;window title\u{07}visible"
        XCTAssertEqual(stripper.feed(bel), "visible")

        let stripper2 = ANSIStripper()
        let st = "\u{1B}]0;title\u{1B}\\visible"
        XCTAssertEqual(stripper2.feed(st), "visible")
    }

    func testHandlesSequenceSplitAcrossChunks() {
        let stripper = ANSIStripper()
        XCTAssertEqual(stripper.feed("abc\u{1B}["), "abc")
        XCTAssertEqual(stripper.feed("31mred"), "red")
    }

    func testKeepsNewlinesAndTabsButDropsOtherControls() {
        let stripper = ANSIStripper()
        let input = "a\tb\nc\u{07}\u{00}d"
        XCTAssertEqual(stripper.feed(input), "a\tb\ncd")
    }
}

final class LineFilterTests: XCTestCase {
    func testKeepsNormalProse() {
        let filter = LineFilter()
        XCTAssertEqual(filter.phrase(for: "I have updated the file."),
                       "I have updated the file.")
    }

    func testCollapsesWhitespace() {
        let filter = LineFilter()
        XCTAssertEqual(filter.phrase(for: "Hello    there\tworld"),
                       "Hello there world")
    }

    func testDropsBoxDrawingNoise() {
        let filter = LineFilter()
        XCTAssertNil(filter.phrase(for: "╭──────────────╮"))
        XCTAssertNil(filter.phrase(for: "│              │"))
    }

    func testStripsDecorativeGlyphsButKeepsText() {
        let filter = LineFilter()
        XCTAssertEqual(filter.phrase(for: "● Running tests"), "Running tests")
    }

    func testDropsBrailleSpinnerFrames() {
        let filter = LineFilter()
        XCTAssertNil(filter.phrase(for: "⠋"))
        XCTAssertNil(filter.phrase(for: "⠙ "))
    }

    func testRespectsMinimumLength() {
        let filter = LineFilter(minMeaningfulCharacters: 5)
        XCTAssertNil(filter.phrase(for: "ok"))
        XCTAssertEqual(filter.phrase(for: "ready"), "ready")
    }

    func testKeepsCJKContent() {
        let filter = LineFilter()
        XCTAssertEqual(filter.phrase(for: "你好世界"), "你好世界")
    }
}

final class OutputProcessorTests: XCTestCase {
    func testSpeaksCompleteLinesOnly() {
        let speaker = RecordingSpeaker()
        let processor = OutputProcessor(speaker: speaker)
        processor.feed("Hello world\npartial")
        XCTAssertEqual(speaker.spoken, ["Hello world"])
        processor.flush()
        XCTAssertEqual(speaker.spoken, ["Hello world", "partial"])
    }

    func testStripsANSIBeforeSpeaking() {
        let speaker = RecordingSpeaker()
        let processor = OutputProcessor(speaker: speaker)
        processor.feed("\u{1B}[32mDone building\u{1B}[0m\n")
        XCTAssertEqual(speaker.spoken, ["Done building"])
    }

    func testCarriageReturnRedrawSpeaksOnlyFinalLine() {
        let speaker = RecordingSpeaker()
        let processor = OutputProcessor(speaker: speaker)
        // A spinner that redraws in place then settles on a final message.
        processor.feed("Working .\rWorking ..\rWorking done\n")
        XCTAssertEqual(speaker.spoken, ["Working done"])
    }

    func testSuppressesDuplicateLines() {
        let speaker = RecordingSpeaker()
        let processor = OutputProcessor(speaker: speaker)
        processor.feed("Same line\nSame line\nDifferent\n")
        XCTAssertEqual(speaker.spoken, ["Same line", "Different"])
    }

    func testIgnoresPureNoise() {
        let speaker = RecordingSpeaker()
        let processor = OutputProcessor(speaker: speaker)
        processor.feed("╭───╮\n│ x │\n╰───╯\nActual message here\n")
        XCTAssertEqual(speaker.spoken, ["Actual message here"])
    }
}

final class ConfigurationTests: XCTestCase {
    func testDefaultsToClaude() throws {
        let config = try Configuration.parse([])
        XCTAssertEqual(config.command, ["claude"])
        XCTAssertFalse(config.mute)
    }

    func testParsesOptions() throws {
        let config = try Configuration.parse(
            ["--voice", "zh-CN", "--rate", "0.5", "--volume", "0.8", "--min-length", "4"])
        XCTAssertEqual(config.voice, "zh-CN")
        XCTAssertEqual(config.rate, 0.5)
        XCTAssertEqual(config.volume, 0.8)
        XCTAssertEqual(config.minMeaningfulCharacters, 4)
        XCTAssertEqual(config.command, ["claude"])
    }

    func testTerminatorSeparatesCommand() throws {
        let config = try Configuration.parse(["--voice", "en-US", "--", "claude", "--resume"])
        XCTAssertEqual(config.voice, "en-US")
        XCTAssertEqual(config.command, ["claude", "--resume"])
    }

    func testFirstPositionalBeginsCommand() throws {
        let config = try Configuration.parse(["npm", "run", "cli"])
        XCTAssertEqual(config.command, ["npm", "run", "cli"])
    }

    func testMuteFlag() throws {
        let config = try Configuration.parse(["--mute"])
        XCTAssertTrue(config.mute)
    }

    func testHelpFlag() throws {
        let config = try Configuration.parse(["--help"])
        XCTAssertTrue(config.showHelp)
    }

    func testMissingValueThrows() {
        XCTAssertThrowsError(try Configuration.parse(["--voice"])) { error in
            XCTAssertEqual(error as? Configuration.ParseError, .missingValue("--voice"))
        }
    }

    func testInvalidNumberThrows() {
        XCTAssertThrowsError(try Configuration.parse(["--rate", "fast"])) { error in
            XCTAssertEqual(error as? Configuration.ParseError,
                           .invalidValue(option: "--rate", value: "fast"))
        }
    }

    func testDefaultEngineIsSystem() throws {
        XCTAssertEqual(try Configuration.parse([]).engine, .system)
    }

    func testParsesEngineAndConfigOptions() throws {
        let config = try Configuration.parse(
            ["--engine", "api", "--config", "/tmp/p.json",
             "--api-url", "https://x", "--api-voice", "alloy", "--api-key", "secret"])
        XCTAssertEqual(config.engine, .api)
        XCTAssertEqual(config.configPath, "/tmp/p.json")
        XCTAssertEqual(config.apiURL, "https://x")
        XCTAssertEqual(config.apiVoice, "alloy")
        XCTAssertEqual(config.apiKey, "secret")
    }

    func testConfigPathImpliesApiEngine() throws {
        let config = try Configuration.parse(["--config", "/tmp/p.json"])
        XCTAssertEqual(config.engine, .api)
    }

    func testInvalidEngineThrows() {
        XCTAssertThrowsError(try Configuration.parse(["--engine", "bogus"])) { error in
            XCTAssertEqual(error as? Configuration.ParseError,
                           .invalidValue(option: "--engine", value: "bogus"))
        }
    }
}

final class TemplateTests: XCTestCase {
    func testRendersBraceValues() {
        let result = Template.render("hello {{name}}!", values: ["name": "world"], environment: [:])
        XCTAssertEqual(result, "hello world!")
    }

    func testRendersEnvironmentValues() {
        let result = Template.render("key=${API_KEY}", values: [:], environment: ["API_KEY": "abc"])
        XCTAssertEqual(result, "key=abc")
    }

    func testUnknownPlaceholdersBecomeEmpty() {
        XCTAssertEqual(Template.render("[{{x}}][${Y}]", values: [:], environment: [:]), "[][]")
    }

    func testHandlesWhitespaceInPlaceholderNames() {
        let result = Template.render("{{ name }} ${ ENV }",
                                     values: ["name": "v"], environment: ["ENV": "e"])
        XCTAssertEqual(result, "v e")
    }

    func testLeavesUnterminatedPlaceholders() {
        XCTAssertEqual(Template.render("a {{ b", values: ["b": "x"], environment: [:]), "a {{ b")
    }

    func testJSONEscape() {
        XCTAssertEqual(Template.jsonEscape("say \"hi\"\nok\t\\"),
                       "say \\\"hi\\\"\\nok\\t\\\\")
    }
}

final class TTSProviderConfigTests: XCTestCase {
    func testDecodesWithDefaults() throws {
        let json = """
        {"url": "https://api.example.com/tts", "body": "{\\"text\\":\\"{{text}}\\"}"}
        """
        let provider = try JSONDecoder().decode(TTSProviderConfig.self, from: Data(json.utf8))
        XCTAssertEqual(provider.url, "https://api.example.com/tts")
        XCTAssertEqual(provider.method, "POST")
        XCTAssertEqual(provider.format, "mp3")
        XCTAssertEqual(provider.timeout, 30)
        XCTAssertTrue(provider.headers.isEmpty)
        XCTAssertNil(provider.audioBase64Field)
    }

    func testBuildRequestEscapesTextAndExpandsEnv() {
        let provider = TTSProviderConfig(
            url: "https://api.example.com/tts",
            headers: ["Authorization": "******",
                      "Content-Type": "application/json"],
            body: "{\"voice\":\"{{voice}}\",\"input\":\"{{text}}\",\"format\":\"{{format}}\"}",
            voice: "alloy",
            format: "wav")

        let request = provider.buildRequest(text: "He said \"hi\"\nbye",
                                            environment: ["HARO_API_KEY": "sk-123"])

        XCTAssertEqual(request.url, "https://api.example.com/tts")
        XCTAssertEqual(request.headers["Authorization"], "******")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        let body = String(decoding: request.body, as: UTF8.self)
        XCTAssertEqual(body,
            "{\"voice\":\"alloy\",\"input\":\"He said \\\"hi\\\"\\nbye\",\"format\":\"wav\"}")
    }
}

final class ProviderResolutionTests: XCTestCase {
    private let providerJSON = Data("""
    {"url": "https://api.example.com/tts", "body": "{\\"input\\":\\"{{text}}\\"}", "voice": "alloy"}
    """.utf8)

    func testSystemEngineReturnsNilProvider() throws {
        let config = try Configuration.parse([])
        let provider = try config.resolveProvider(load: { _ in Data() })
        XCTAssertNil(provider)
    }

    func testApiEngineWithoutConfigThrows() {
        let config = Configuration(engine: .api)
        XCTAssertThrowsError(try config.resolveProvider(load: { _ in Data() }))
    }

    func testLoadsProviderFromInjectedLoader() throws {
        let config = try Configuration.parse(["--config", "/path/p.json"])
        let provider = try config.resolveProvider(load: { path in
            XCTAssertEqual(path, "/path/p.json")
            return self.providerJSON
        })
        XCTAssertEqual(provider?.url, "https://api.example.com/tts")
        XCTAssertEqual(provider?.voice, "alloy")
    }

    func testCLIOverridesAreApplied() throws {
        let config = try Configuration.parse(
            ["--config", "/p.json", "--api-url", "https://override", "--api-voice", "nova"])
        let provider = try config.resolveProvider(load: { _ in self.providerJSON })
        XCTAssertEqual(provider?.url, "https://override")
        XCTAssertEqual(provider?.voice, "nova")
    }

    func testInvalidJSONThrowsDecodeError() {
        let config = try! Configuration.parse(["--config", "/p.json"])
        XCTAssertThrowsError(try config.resolveProvider(load: { _ in Data("not json".utf8) }))
    }
}
