import Foundation
import Observation

/// Tracks the phase and progress of a clippings file import.
@Observable
final class ImportState {
    var phase: ImportPhase = .idle
    var progress: Double = 0.0
    var currentBook: String? = nil
    var summary: ImportSummary? = nil

    var isRunning: Bool { phase == .running }
}

/// The discrete phases of an import operation.
enum ImportPhase: Equatable {
    case idle
    case running
    case completed
    case failed(String)
}

/// Statistics shown to the user after an import completes.
struct ImportSummary: Equatable {
    let totalClippings: Int
    let newClippings: Int
    let totalBooks: Int
    let newBooks: Int
    let duration: TimeInterval
}
