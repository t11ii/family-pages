import Foundation

/// Runs command-line tools (git, gh, publish.sh) off the main thread.
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
        var trimmed: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func run(_ args: [String], cwd: String) async -> Result {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)

            // Apps launched from Finder get a minimal PATH, so add Homebrew's.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            env["GIT_TERMINAL_PROMPT"] = "0" // fail instead of hanging on a password prompt
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return Result(status: -1, output: error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }
}
