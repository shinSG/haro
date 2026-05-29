# haro

`haro` 是一个 macOS 命令行程序，用来**监听本地终端里 Claude Code 的运行进程**，把
Claude Code 输出的文字通过文字转语音（TTS）实时**朗读出来**。

它通过一个伪终端（PTY）来启动并“包裹” `claude` 命令：你的键盘输入和 Claude Code
的界面会原样转发到终端（使用体验和直接运行 `claude` 一致），同时 `haro` 会在后台
捕获输出、清理终端控制字符、过滤界面噪音，并把有意义的文本朗读出来。

TTS 支持两种后端：

- **`system`（默认）**：使用 macOS 本机语音（`AVSpeechSynthesizer`），无需联网。
- **`api`**：调用**可配置的第三方 TTS 服务**（如 OpenAI、ElevenLabs、Google 等），
  通过一个 JSON 配置文件描述接口（URL、请求头、请求体模板、音色、音频格式），
  返回的音频用 `afplay` 播放。

> 仅支持 macOS（依赖伪终端与音频播放）。

## 工作原理

```
你的终端  ⇄  haro (PTY 包裹)  ⇄  claude code 进程
                  │
                  ├─ 原样转发输入/界面到终端
                  └─ 捕获输出 → 去除 ANSI 转义 → 过滤噪音 → TTS 朗读
                                                          ├─ system: AVSpeechSynthesizer
                                                          └─ api:    第三方 HTTP 服务 → afplay
```

- **PTY 包裹**：`forkpty` 启动 `claude`，I/O 透明转发，并跟随窗口大小变化（`SIGWINCH`）。
- **去除 ANSI**：剥离颜色、光标移动、清屏、窗口标题等转义序列与控制字符。
- **噪音过滤**：丢弃边框、spinner（包括盲文 spinner 帧）、纯符号等装饰性内容，
  对就地重绘（回车 `\r`）只朗读最终结果，并抑制连续重复行。
- **语音合成**：本机语音或可配置的第三方 TTS API。

## 构建与安装

需要 Xcode 命令行工具（提供 Swift 工具链）。

```bash
# 构建发布版
swift build -c release

# 安装到 PATH（可选）
cp .build/release/haro /usr/local/bin/
```

## 使用

```bash
# 监听并朗读 Claude Code（默认运行 `claude`）
haro

# 指定中文语音与语速
haro --voice zh-CN --rate 0.5

# 向被监听的命令传参：使用 `--` 分隔
haro -- claude --resume

# 也可以监听任意命令行程序
haro --voice en-US -- npm run some-cli

# 只透传、不朗读
haro --mute
```

### 选项

| 选项 | 说明 |
| --- | --- |
| `--engine <system\|api>` | 选择 TTS 后端。`system` 用本机语音；`api` 调用第三方服务。默认 `system`（指定 `--config` 时自动切到 `api`）。 |
| `--config <file>` | 描述第三方 TTS 服务的 JSON 配置文件（接口 URL、请求头、请求体模板、音色、音频格式）。会自动启用 `api` 引擎。 |
| `--api-url <url>` | 覆盖配置文件里的接口 URL。 |
| `--api-voice <id>` | 覆盖配置文件里的音色/模型。 |
| `--api-key <key>` | 密钥，会以环境变量 `${HARO_API_KEY}` 暴露给配置模板（避免把密钥写进文件）。 |
| `--voice <id\|lang>` | `system` 引擎：语音标识或语言代码，例如 `zh-CN`、`en-US`，或完整的 `com.apple.voice.compact.en-US.Samantha`。 |
| `--rate <0.0-1.0>` | `system` 引擎：朗读语速（`AVSpeechUtterance` 标度）。 |
| `--volume <0.0-1.0>` | `system` 引擎：朗读音量。 |
| `--min-length <n>` | 一行至少包含多少个“有效字符”才朗读（默认 2），调大可减少碎碎念。 |
| `--mute` | 只转发输出、不朗读。 |
| `-h, --help` | 显示帮助。 |

查看本机（`system` 引擎）可用语音：

```bash
say -v '?'
```

## 配置第三方 TTS 服务（`api` 引擎）

第三方服务通过一个 JSON 配置文件描述，字段如下：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `url` | 是 | 接口地址，可包含 `${ENV}` 占位符。 |
| `method` | 否 | HTTP 方法，默认 `POST`。 |
| `headers` | 否 | 请求头；值可用 `${ENV}`（如密钥）和 `{{...}}` 占位符。 |
| `body` | 是 | 请求体模板，支持占位符 `{{text}}`（已做 JSON 转义）、`{{voice}}`、`{{format}}`、`{{rate}}`，以及 `${ENV}`。 |
| `voice` | 否 | 传给 `{{voice}}` 的音色/模型标识。 |
| `format` | 否 | 请求并用作播放文件扩展名的音频格式（`mp3`/`wav`/`aac`…），默认 `mp3`。 |
| `rate` | 否 | 通过 `{{rate}}` 暴露给模板的语速。 |
| `audioBase64Field` | 否 | 若返回的是 JSON，则按该（支持点号分隔的）键路径读取 base64 音频，例如 `audioContent`、`data.audio`。不填则把响应体直接当作音频。 |
| `timeout` | 否 | 请求超时（秒），默认 30。 |

**占位符**：`{{...}}` 来自合成参数（`text`/`voice`/`format`/`rate`），`${...}` 来自进程环境变量
（推荐用来注入密钥）。`{{text}}` 会自动做 JSON 转义。

**密钥**：不要把密钥写进配置文件，请在 `headers`/`url` 中用 `${HARO_API_KEY}` 这类占位符引用，
然后通过命令行 `--api-key`，或导出对应环境变量来提供。

`examples/` 目录提供了可直接参考的配置：`openai-tts.json`、`elevenlabs-tts.json`、`google-tts.json`。

示例（OpenAI 兼容接口，`examples/openai-tts.json`）：

```json
{
  "url": "https://api.openai.com/v1/audio/speech",
  "method": "POST",
  "headers": {
    "Authorization": "Bearer ${HARO_API_KEY}",
    "Content-Type": "application/json"
  },
  "body": "{\"model\":\"tts-1\",\"voice\":\"{{voice}}\",\"input\":\"{{text}}\",\"response_format\":\"{{format}}\"}",
  "voice": "alloy",
  "format": "mp3"
}
```

使用：

```bash
# 用第三方服务朗读 Claude Code 的输出
haro --config examples/openai-tts.json --api-key sk-xxxx

# 覆盖音色，并把参数透传给被监听命令
haro --config examples/openai-tts.json --api-voice nova -- claude --resume
```

返回 JSON+base64 音频的服务（如 Google），配置 `audioBase64Field` 即可，例如：

```bash
export HARO_API_KEY=your-key
haro --config examples/google-tts.json --api-voice cmn-CN
```

## 项目结构

- `Sources/HaroCore/` — 与平台无关的核心逻辑（参数解析、ANSI 去除、行过滤、输出管线、
  第三方 TTS 配置与请求模板渲染），有单元测试覆盖。
- `Sources/haro/` — macOS 可执行程序：PTY 包裹（`PTYRunner`）、本机语音后端
  （`SystemSpeaker`）与第三方 TTS 后端（`RemoteTTSSpeaker`）。
- `Tests/HaroCoreTests/` — 核心逻辑的单元测试。
- `examples/` — 第三方 TTS 服务的示例配置（OpenAI / ElevenLabs / Google）。

## 测试

```bash
swift test
```

## 已知限制

- Claude Code 是富文本 TUI，会频繁重绘；`haro` 用启发式规则尽量只朗读有意义的文本，
  可通过 `--min-length` 微调。
