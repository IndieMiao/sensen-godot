import Foundation
import Network

/// Control transport only. The media owner supplies the launch key, a capability gate and typed commands.
/// Never initialized from +load in this first segment: incomplete media/Block support must stay unavailable.
/// mediaReady means the implementation is complete, NOT that a room is connected (CONNECT needs CAPS first).
@MainActor
final class VoiceDatagramServer {
    enum Fault { case listener, peerLost, deliveryExpired, eventRejected }
    private let key: String
    private let mediaReady: () -> Bool
    private let command: (VoiceWireCommand) -> Void
    private let fault: (Fault) -> Void
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var client: NWConnection?
    private var delivery = VoiceEventDelivery()
    private var timer: DispatchSourceTimer?
    private var running = false
    private var retryGeneration = 0
    private let clock: () -> TimeInterval

    init(key: String, mediaReady: @escaping () -> Bool = { false },
         command: @escaping (VoiceWireCommand) -> Void, fault: @escaping (Fault) -> Void,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.key = key
        self.mediaReady = mediaReady
        self.command = command
        self.fault = fault
        self.clock = clock
    }

    deinit {
        timer?.cancel()
        listener?.cancel()
        for peer in connections.values { peer.cancel() }
    }

    func start() {
        guard !running, VoiceWire.validKey(key) else { return }
        running = true
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + VoiceEventDelivery.retryInterval, repeating: VoiceEventDelivery.retryInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.retryEvents() }
        }
        self.timer = timer
        timer.resume()
        listen()
    }

    func stop() {
        running = false
        retryGeneration += 1
        timer?.cancel(); timer = nil
        listener?.cancel(); listener = nil
        // Detach before cancel callbacks so an intentional stop does not report a second fault.
        client = nil
        let peers = Array(connections.values)
        connections.removeAll()
        for peer in peers { peer.cancel() }
        delivery.clear()
    }

    /// Media owner uses this on session teardown to avoid replaying an obsolete session's unacked events.
    func discardPendingEvents() { delivery.clear() }

    func publish(_ event: [String: Any]) {
        guard running, client != nil, mediaReady() else { return }
        do { send(try delivery.enqueue(event, now: clock())) }
        catch { failDelivery(.eventRejected) }
    }

    private func listen() {
        guard running, listener == nil else { return }
        do {
            let parameters = NWParameters.udp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: VoiceWire.port)!)
            let next = try NWListener(using: parameters)
            listener = next
            next.stateUpdateHandler = { [weak self, weak next] state in
                Task { @MainActor in
                    guard let self, let next, self.listener === next else { return }
                    if case .failed = state { self.listenerFailed() }
                }
            }
            next.newConnectionHandler = { [weak self, weak next] peer in
                Task { @MainActor in
                    guard let self else { peer.cancel(); return }
                    // Keep the emitting listener's identity across the actor hop. A peer queued by an old
                    // listener is not in connections yet and must be cancelled even if a new round is running.
                    VoiceListenerHandoff.deliver(running: self.running, current: self.listener, source: next,
                                                peer: peer, accept: self.accept, cancel: { $0.cancel() })
                }
            }
            next.start(queue: .main)
        } catch { listenerFailed() }
    }

    private func listenerFailed() {
        guard running else { return }
        listener?.cancel(); listener = nil
        let peers = Array(connections.values)
        connections.removeAll(); client = nil
        for peer in peers { peer.cancel() }
        delivery.clear()
        fault(.listener) // Caller disconnects media; never keep a room alive without a control channel.
        retryGeneration += 1
        let expected = retryGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.running, self.retryGeneration == expected else { return }
            self.listen()
        }
    }

    private func accept(_ peer: NWConnection) {
        // Bound unauthenticated UDP endpoints. They are never the event client until a valid packet arrives.
        guard running, connections.count < 8 else { peer.cancel(); return }
        let id = ObjectIdentifier(peer)
        connections[id] = peer
        peer.stateUpdateHandler = { [weak self, weak peer] state in
            Task { @MainActor in
                guard let self, let peer, self.connections[id] === peer else { return }
                switch state {
                case .failed, .cancelled: self.remove(peer)
                default: break
                }
            }
        }
        peer.start(queue: .main)
        receive(peer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak peer] in
            guard let self, let peer, self.connections[id] === peer, self.client !== peer else { return }
            self.remove(peer)
        }
    }

    private func remove(_ peer: NWConnection) {
        guard connections.removeValue(forKey: ObjectIdentifier(peer)) != nil else { return }
        let wasClient = client === peer
        if wasClient { client = nil; delivery.clear() }
        peer.cancel()
        if wasClient && running { fault(.peerLost) }
    }

    private func receive(_ peer: NWConnection) {
        peer.receiveMessage { [weak self, weak peer] data, _, _, error in
            Task { @MainActor in
                guard let self, let peer, self.running, self.connections[ObjectIdentifier(peer)] === peer else { return }
                guard error == nil else { self.remove(peer); return }
                guard let data, let request = VoiceWire.decode(data, key: self.key) else {
                    // Invalid authentication must not even disconnect an already authenticated client's room.
                    // A new untrusted endpoint is discarded; the current client simply gets no answer.
                    if self.client === peer { self.receive(peer) } else { self.remove(peer) }
                    return
                }
                if self.client !== peer {
                    let previous = self.client
                    self.client = peer
                    if let previous { self.remove(previous) }
                }
                switch request {
                case .capabilities:
                    self.send(self.mediaReady() ? VoiceWire.available : VoiceWire.unavailable)
                case .acknowledge(let id): self.delivery.acknowledge(id)
                default:
                    if self.mediaReady() { self.command(request) }
                }
                self.receive(peer)
            }
        }
    }

    private func retryEvents() {
        guard running else { return }
        let result = delivery.poll(now: clock())
        if result.expired { failDelivery(.deliveryExpired); return }
        for packet in result.packets { send(packet) }
    }

    private func failDelivery(_ reason: Fault) {
        delivery.clear()
        fault(reason) // A missing terminal event must not silently leave a native microphone/room running.
    }

    private func send(_ packet: Data) {
        guard let peer = client else { return }
        peer.send(content: packet, completion: .contentProcessed { [weak self, weak peer] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, let peer, self.client === peer else { return }
                self.remove(peer)
            }
        })
    }
}
