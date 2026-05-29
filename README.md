# haro

`haro` 是一个 macOS 命令行程序，用来**监听本地终端里 Claude Code 的运行进程**，把
Claude Code 输出的文字通过系统的文字转语音（TTS）引擎实时**朗读出来**。

它通过一个伪终端（PTY）来启动并“包裹” `claude` 命令：你的键盘输入和 Claude Code
的界面会原样转发到终端（使用体验和直接运行 `claude` 一致），同时 `haro` 会在后台
捕获输出、清理终端控制字符、过滤界面噪音，并用 `AVSpeechSynthesizer` 朗读有意义的文本。

> 仅支持 macOS（依赖伪终端与 AVFoundation 语音合成）。

## 工作原理

```
你的终端  ⇄  haro (PTY 包裹)  ⇄  claude code 进程
                  │
                  ├─ 原样转发输入/界面到终端
                  └─ 捕获输出 → 去除 ANSI 转义 → 过滤噪音 → TTS 朗读
```

- **PTY 包裹**：`forkpty` 启动 `claude`，I/O 透明转发，并跟随窗口大小变化（`SIGWINCH`）。
- **去除 ANSI**：剥离颜色、光标移动、清屏、窗口标题等转义序列与控制字符。
- **噪音过滤**：丢弃边框、spinner（包括盲文 spinner 帧）、纯符号等装饰性内容，
  对就地重绘（回车 `\r`）只朗读最终结果，并抑制连续重复行。
- **语音合成**：使用系统语音，支持选择音色/语言、语速、音量。

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
| `--voice <id\|lang>` | 语音标识或语言代码，例如 `zh-CN`、`en-US`，或完整的 `com.apple.voice.compact.en-US.Samantha`。 |
| `--rate <0.0-1.0>` | 朗读语速（`AVSpeechUtterance` 标度）。 |
| `--volume <0.0-1.0>` | 朗读音量。 |
| `--min-length <n>` | 一行至少包含多少个“有效字符”才朗读（默认 2），调大可减少碎碎念。 |
| `--mute` | 只转发输出、不朗读。 |
| `-h, --help` | 显示帮助。 |

查看本机可用语音：

```bash
say -v '?'
```

## 项目结构

- `Sources/HaroCore/` — 与平台无关的核心逻辑（参数解析、ANSI 去除、行过滤、输出管线），有单元测试覆盖。
- `Sources/haro/` — macOS 可执行程序：PTY 包裹（`PTYRunner`）与系统语音后端（`SystemSpeaker`）。
- `Tests/HaroCoreTests/` — 核心逻辑的单元测试。

## 测试

```bash
swift test
```

## 已知限制

- Claude Code 是富文本 TUI，会频繁重绘；`haro` 用启发式规则尽量只朗读有意义的文本，
  可通过 `--min-length` 微调。
