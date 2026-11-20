import Foundation

/// Installed on LiveKit's capture-postprocessing path before any microphone publication. Retiring only takes this
/// small in-memory lock; it never waits for an SDK worker, signalling request, connect or microphone Task.
final class VoiceCaptureGate: @unchecked Sendable {
    enum Failure: Error { case retired }
    private let lock = NSLock()
    private var enabled = false
    private var closedPermanently = false

    var retired: Bool {
        lock.lock(); defer { lock.unlock() }
        return closedPermanently
    }

    func setEnabled(_ enabled: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        guard !closedPermanently else { throw Failure.retired }
        self.enabled = enabled
    }

    func retire() {
        lock.lock(); defer { lock.unlock() }
        closedPermanently = true
        enabled = false
    }

    /// Callback body only zeros the current frame in place. Never records, copies, logs or forwards PCM.
    /// Hold the lock through zeroing so retire() and frame processing have an explicit ordering.
    func filter(silence: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        if !enabled || closedPermanently { silence() }
    }
}
