import Foundation
import OSLog

/// Signpost instrumentation for the wallpaper apply path.
///
/// The apply pipeline crosses four subsystems — our render, Core Image, ImageIO, and the
/// system's wallpaper agent — and a previous round of "fix the freezes" optimised the wrong one
/// because nobody had measured where the time actually went. Every stage is signposted now, so
/// the next performance question gets answered with a number instead of a guess.
///
/// Signposts are always emitted (they are nearly free and show up in Instruments). The textual
/// per-stage log is opt-in via `KINDLEWALL_PERF=1`.
enum Perf {
    static let signposter = OSSignposter(subsystem: Constants.App.bundleIdentifier, category: "apply")
    private static let logger = Logger(subsystem: Constants.App.bundleIdentifier, category: "perf")

    /// Whether to log a per-stage timing line. Opt-in: `KINDLEWALL_PERF=1`.
    static let isVerbose = ProcessInfo.processInfo.environment["KINDLEWALL_PERF"] == "1"

    /// Runs `body` inside a signpost interval, logging its duration when verbose.
    /// - Parameters:
    ///   - name: Signpost interval name; also the log prefix.
    ///   - detail: Extra context for the log line (frame count, byte size, …).
    /// `detail` is a plain `String` rather than an `@autoclosure`: with a defaulted autoclosure
    /// in front of it, Swift binds a trailing closure to `detail` instead of `body`. Building a
    /// short string per stage is not worth the call-site sharp edge.
    static func measure<T>(_ name: StaticString,
                           _ detail: String = "",
                           _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now()
        defer {
            signposter.endInterval(name, state)
            if isVerbose {
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                log("\(name)", detail, ms)
            }
        }
        return try body()
    }

    /// Logs one finished stage. Public so callers that cannot wrap a closure (async stages,
    /// callbacks) can still report into the same stream.
    static func log(_ stage: String, _ detail: String = "", _ milliseconds: Double) {
        guard isVerbose else { return }
        let suffix = detail.isEmpty ? "" : " (\(detail))"
        logger.info("⏱ \(stage, privacy: .public)\(suffix, privacy: .public) — \(milliseconds, format: .fixed(precision: 1)) ms")
        // Also to stdout. `Logger.info` is memory-only until something asks for it, and reading
        // it back out of `log show` from a locally built binary is unreliable — which is exactly
        // when these numbers are wanted. Launch with `KINDLEWALL_PERF=1 …/KindleWall` and read
        // the terminal.
        print(String(format: "⏱ %@%@ — %.1f ms", stage, suffix, milliseconds))
        fflush(stdout)
    }

    /// A stopwatch for stages that span an `await` and cannot use `measure`.
    struct Clock {
        private let start = DispatchTime.now()
        let stage: String
        init(_ stage: String) { self.stage = stage }
        var milliseconds: Double {
            Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        }
        func finish(_ detail: String = "") { Perf.log(stage, detail, milliseconds) }
    }
}
