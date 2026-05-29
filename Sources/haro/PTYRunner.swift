import Foundation
import HaroCore

#if os(macOS)
import Darwin

/// Set by the SIGWINCH handler; checked in the I/O loop to resize the child PTY.
private var haroWinchPending: sig_atomic_t = 0
private func haroHandleWinch(_ sig: Int32) { haroWinchPending = 1 }

/// Launches a command inside a pseudo-terminal and shuttles bytes between the
/// user's real terminal and the child, while feeding the child's output to an
/// `OutputProcessor` for text-to-speech.
public final class PTYRunner {
    private let processor: OutputProcessor

    public init(processor: OutputProcessor) {
        self.processor = processor
    }

    /// Run `command` (argv) attached to a PTY. Returns the child exit status.
    public func run(command: [String]) -> Int32 {
        precondition(!command.isEmpty, "command must not be empty")

        // Snapshot the current terminal so we can mirror it into the PTY and
        // restore it on exit.
        var savedTermios = termios()
        let stdinIsTTY = isatty(STDIN_FILENO) != 0
        if stdinIsTTY {
            tcgetattr(STDIN_FILENO, &savedTermios)
        }

        var winSize = winsize()
        if ioctl(STDOUT_FILENO, UInt(truncatingIfNeeded: TIOCGWINSZ), &winSize) != 0 {
            // Sensible default if stdout is not a TTY.
            winSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        }

        var master: Int32 = -1
        var childTermios = savedTermios
        let pid = withUnsafeMutablePointer(to: &childTermios) { tptr in
            withUnsafeMutablePointer(to: &winSize) { wptr in
                forkpty(&master, nil, stdinIsTTY ? tptr : nil, wptr)
            }
        }

        if pid < 0 {
            perror("haro: forkpty")
            return 1
        }

        if pid == 0 {
            // Child: exec the target command. stdio is already the PTY slave.
            execChild(command)
            // execvp only returns on failure.
            perror("haro: exec \(command[0])")
            _exit(127)
        }

        // Parent.
        if stdinIsTTY {
            enterRawMode(from: savedTermios)
        }
        defer {
            if stdinIsTTY {
                tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios)
            }
        }

        signal(SIGWINCH, haroHandleWinch)

        let status = ioLoop(master: master, childPID: pid)
        processor.flush()
        return status
    }

    // MARK: - Child

    private func execChild(_ command: [String]) {
        // Build a null-terminated argv array of C strings.
        var cArgs: [UnsafeMutablePointer<CChar>?] = command.map { strdup($0) }
        cArgs.append(nil)
        _ = execvp(command[0], &cArgs)
        // strdup'd memory is irrelevant after a failed exec; the process exits.
    }

    // MARK: - Parent I/O loop

    private func ioLoop(master: Int32, childPID: pid_t) -> Int32 {
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        var fds = [pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
                   pollfd(fd: master, events: Int16(POLLIN), revents: 0)]

        var running = true
        while running {
            if haroWinchPending != 0 {
                haroWinchPending = 0
                var ws = winsize()
                if ioctl(STDOUT_FILENO, UInt(truncatingIfNeeded: TIOCGWINSZ), &ws) == 0 {
                    _ = ioctl(master, UInt(truncatingIfNeeded: TIOCSWINSZ), &ws)
                }
            }

            let ready = poll(&fds, nfds_t(fds.count), -1)
            if ready < 0 {
                if errno == EINTR { continue }   // interrupted by SIGWINCH
                break
            }

            // Forward user keystrokes into the child.
            if fds[0].revents & Int16(POLLIN) != 0 {
                let n = read(STDIN_FILENO, &buffer, bufferSize)
                if n > 0 {
                    writeAll(master, buffer, n)
                } else if n == 0 {
                    // stdin closed: stop forwarding but keep draining the child.
                    fds[0].events = 0
                }
            }

            // Mirror child output to the terminal and speak it.
            if fds[1].revents & Int16(POLLIN) != 0 {
                let n = read(master, &buffer, bufferSize)
                if n > 0 {
                    writeAll(STDOUT_FILENO, buffer, n)
                    feedProcessor(buffer, count: n)
                } else {
                    // EOF or error on the PTY master: the child has exited.
                    running = false
                }
            }

            if (fds[1].revents & Int16(POLLHUP | POLLERR)) != 0 {
                running = false
            }
        }

        return reapChild(childPID)
    }

    private func feedProcessor(_ buffer: [UInt8], count: Int) {
        let chunk = String(decoding: buffer[0..<count], as: UTF8.self)
        processor.feed(chunk)
    }

    private func writeAll(_ fd: Int32, _ buffer: [UInt8], _ count: Int) {
        var written = 0
        buffer.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.baseAddress!
            while written < count {
                let n = write(fd, base + written, count - written)
                if n > 0 {
                    written += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }

    private func reapChild(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR { /* retry */ }
        if (status & 0x7f) == 0 {            // WIFEXITED
            return (status >> 8) & 0xff      // WEXITSTATUS
        }
        return 128 + (status & 0x7f)         // killed by signal
    }

    // MARK: - Terminal mode

    private func enterRawMode(from original: termios) {
        var raw = original
        cfmakeraw(&raw)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }
}
#endif
