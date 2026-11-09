import Foundation

/// An attention moment the app can announce. The app chooses the sound.
public enum AlertCue: Sendable, Equatable {
    case blocked
    case completion
}

/// Episodes already announced from a source without a sequence number. The
/// next snapshot absorbs the matching transition instead of repeating it.
struct PendingAlertCues: Sendable, Equatable {
    var blocked: Set<PaneID> = []
    var completionSequence: Set<PaneID> = []
}
