import Foundation

/// Deterministic delayed-delivery regression. No NWListener/socket, timing sleeps, audio or SDK dependency.
/// The same handoff gate is used inside VoiceDatagramServer's MainActor Task, before accept can register a peer.
@main
struct VoiceListenerHandoffChecks {
    final class Listener {}
    final class Peer {
        var cancelled = 0
        var accepted = 0
    }
    final class Owner {
        var running = false
        var listener: Listener?
        var connections: [Peer] = []
        var client: Peer?
        var commands = 0

        func start(_ source: Listener) { running = true; listener = source }
        func stop() { running = false; listener = nil; connections = []; client = nil }
        func failed() { listener = nil; connections = []; client = nil } // Retry wait still has running=true.

        /// Capture as the Network callback does, but let the test deliver the queued actor task explicitly.
        func delayed(from source: Listener, peer: Peer) -> () -> Void {
            { [weak self, weak source] in
                guard let self else { peer.cancelled += 1; return }
                VoiceListenerHandoff.deliver(running: self.running, current: self.listener, source: source,
                    peer: peer, accept: { peer in
                        peer.accepted += 1
                        self.connections.append(peer)
                        // Model the strongest downstream effect of a valid-key packet, so reject must stop all three.
                        self.client = peer
                        self.commands += 1
                    }, cancel: { $0.cancelled += 1 })
            }
        }
    }
    static var checks = 0
    static var failures = 0
    static func check(_ result: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if !result() { failures += 1; print("FAIL: \(label)") }
    }
    static func main() {
        let owner = Owner(), first = Listener(), second = Listener()
        owner.start(first)
        let obsolete = Peer(), pending = owner.delayed(from: first, peer: obsolete)
        owner.stop()
        owner.start(second)
        let live = Peer()
        owner.delayed(from: second, peer: live)()
        pending() // L1 callback arrives after stop/start AND after an L2 client already exists.
        check(obsolete.cancelled == 1 && obsolete.accepted == 0, "stop/start cancels late L1")
        check(owner.connections.count == 1 && owner.connections.first === live, "late L1 not registered")
        check(owner.client === live && owner.commands == 1, "late L1 cannot replace L2 client or dispatch")
        check(live.cancelled == 0 && live.accepted == 1, "L2 remains usable")

        let failedOwner = Owner(), failedListener = Listener()
        failedOwner.start(failedListener)
        let afterFailure = Peer(), failedPending = failedOwner.delayed(from: failedListener, peer: afterFailure)
        failedOwner.failed()
        check(failedOwner.running && failedOwner.listener == nil, "failure wait is running without listener")
        failedPending()
        check(afterFailure.cancelled == 1 && afterFailure.accepted == 0, "late callback rejected while awaiting retry")
        check(failedOwner.connections.isEmpty && failedOwner.client == nil && failedOwner.commands == 0,
              "failed listener cannot create a control destination")
        let restarted = Listener(), retryPeer = Peer()
        failedOwner.start(restarted)
        failedOwner.delayed(from: restarted, peer: retryPeer)()
        check(retryPeer.accepted == 1 && failedOwner.client === retryPeer, "new retry listener accepts normally")

        let stopped = Peer(), stoppedPending = owner.delayed(from: second, peer: stopped)
        owner.stop(); stoppedPending()
        check(stopped.cancelled == 1 && stopped.accepted == 0, "stopped owner rejects late peer")
        var releasedListener: Listener? = Listener()
        owner.start(releasedListener!)
        let released = Peer(), releasedPending = owner.delayed(from: releasedListener!, peer: released)
        owner.failed(); releasedListener = nil
        owner.start(Listener()); releasedPending()
        check(released.cancelled == 1 && released.accepted == 0, "deallocated source listener rejects, no identity reuse")

        var releasedOwner: Owner? = Owner()
        releasedOwner!.start(first)
        let orphan = Peer(), orphanPending = releasedOwner!.delayed(from: first, peer: orphan)
        releasedOwner = nil; orphanPending()
        check(orphan.cancelled == 1 && orphan.accepted == 0, "released owner still cancels unregistered peer")
        print("VOICE_LISTENER_HANDOFF_CHECKS \(checks) passed=\(checks - failures) failed=\(failures); deterministic delivery, no sockets")
        if failures > 0 { exit(1) }
    }
}
