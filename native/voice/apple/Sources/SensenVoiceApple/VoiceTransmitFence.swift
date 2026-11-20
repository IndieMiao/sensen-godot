/// Independent of the room's serialized async controls. The backend supplies an in-memory capture-frame gate,
/// not a synchronous SDK API that could itself wait for an occupied RTC worker. Retirement never reopens it.
@MainActor
final class VoiceTransmitFence {
    enum Failure: Error { case retired, stopUnconfirmed }
    private let availability: (Bool, Bool) throws -> Void
    private var engaged = false
    private(set) var retired = false
    private(set) var stopConfirmed = true

    init(availability: @escaping (Bool, Bool) throws -> Void) { self.availability = availability }

    func checkActive() throws {
        guard !retired else { throw Failure.retired }
    }

    func prepare() throws {
        try checkActive()
        engaged = true
        try availability(false, true) // Connecting/receiving alone never enables microphone input.
    }

    func microphone(_ enabled: Bool) throws {
        try checkActive()
        engaged = true
        try availability(enabled, true)
    }

    @discardableResult
    func retire() -> Bool {
        guard !retired else { return stopConfirmed } // An old cleanup must not touch a replacement's audio engine.
        retired = true
        guard engaged else { return true }
        stopConfirmed = false
        do {
            try availability(false, false)
            stopConfirmed = true
        } catch { /* Caller reports stop unconfirmed and never enables a replacement over this owner. */ }
        return stopConfirmed
    }
}
