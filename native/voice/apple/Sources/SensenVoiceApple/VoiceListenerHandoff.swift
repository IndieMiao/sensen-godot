/// Called on the owning actor AFTER an asynchronous listener callback is delivered.
/// Checking before the hop is insufficient: stop/start or listener failure may occur while it is queued.
enum VoiceListenerHandoff {
    static func deliver<Listener: AnyObject, Peer>(running: Bool, current: Listener?, source: Listener?,
                                                  peer: Peer, accept: (Peer) -> Void, cancel: (Peer) -> Void) {
        guard running, let current, let source, current === source else {
            cancel(peer) // This peer was never registered, so normal stop/failure cleanup cannot find it.
            return
        }
        accept(peer)
    }
}
