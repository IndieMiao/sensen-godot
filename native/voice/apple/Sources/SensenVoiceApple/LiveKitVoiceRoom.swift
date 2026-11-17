import Foundation
import LiveKit

/// SDK-specific calls live here; the controller tests use the same protocol with suspended fake operations.
@MainActor
final class LiveKitVoiceRoom: NSObject, VoiceMediaRoom, RoomDelegate, @unchecked Sendable {
    var event: ((VoiceRoomEvent) -> Void)?
    private var room: Room!
    private var listening = true
    private var volumesByIdentity: [String: Double] = [:]
    private var blockedIdentities: Set<String> = []

    override init() {
        super.init()
        room = Room(delegate: self)
    }

    func connect(url: String, token: String) async throws {
        try await room.connect(url: url, token: token, connectOptions: ConnectOptions(autoSubscribe: false))
    }

    func disconnect() async { event = nil; await room.disconnect() }
    func microphone(_ enabled: Bool) async throws { try await room.localParticipant.setMicrophone(enabled: enabled) }

    func permissions(denied: Set<String>) async throws {
        // Swift 2.19's permission API uses participant SID, not Android's identity field.
        // With a deny list, use an explicit allow list: unknown/new peers remain denied until their callback runs.
        let allowed = room.remoteParticipants.values.compactMap { person -> ParticipantTrackPermission? in
            guard let identity = person.identity?.stringValue, !denied.contains(identity), let sid = person.sid else { return nil }
            return ParticipantTrackPermission(participantSid: sid.stringValue, allTracksAllowed: true)
        }
        try await room.localParticipant.setTrackSubscriptionPermissions(allParticipantsAllowed: denied.isEmpty,
                                                                         trackPermissions: denied.isEmpty ? [] : allowed)
    }

    func subscriptions(blocked: Set<String>) async throws {
        for participant in room.remoteParticipants.values {
            guard let identity = participant.identity?.stringValue else { continue }
            for publication in participant.trackPublications.values {
                guard let remote = publication as? RemoteTrackPublication else { continue }
                // No remote cameras/screens/data are requested by this voice-only bridge.
                try await remote.set(subscribed: remote.kind == .audio && !blockedIdentities.contains(identity))
                try Task.checkCancellation()
            }
        }
    }

    func volumes(listening: Bool, values: [String: Double], blocked: Set<String>) {
        self.listening = listening; volumesByIdentity = values; blockedIdentities = blocked
        applyVolumes()
    }

    private func applyVolumes() {
        for participant in room.remoteParticipants.values {
            let who = participant.identity?.stringValue ?? ""
            let volume = listening && !blockedIdentities.contains(who) ? volumesByIdentity[who] ?? 1 : 0
            for publication in participant.trackPublications.values {
                (publication.track as? RemoteAudioTrack)?.volume = volume
            }
        }
    }

    var participants: [VoiceParticipantState] {
        let all: [Participant] = [room.localParticipant] + room.remoteParticipants.values.sorted {
            ($0.identity?.stringValue ?? "") < ($1.identity?.stringValue ?? "")
        }
        return all.compactMap { p in
            guard let id = p.identity?.stringValue else { return nil }
            let local = p === room.localParticipant
            // Publication metadata is authoritative immediately after setMicrophone, without a delayed derived flow.
            let mic = p.trackPublications.values.first(where: { $0.source == .microphone }).map { !$0.isMuted } ?? false
            let audible = p.trackPublications.values.contains {
                guard let remote = $0 as? RemoteTrackPublication else { return false }
                return remote.isSubscribed && remote.track is RemoteAudioTrack
            }
            return VoiceParticipantState(identity: id, name: p.name ?? String(id.prefix(8)), local: local,
                                         speaking: p.isSpeaking, microphone: mic, subscribedAudio: audible)
        }
    }

    nonisolated private func notify(_ source: Room, _ event: VoiceRoomEvent) {
        Task { @MainActor [weak self] in
            guard let self, self.room === source else { return }
            self.applyVolumes() // Never announce or play a newly subscribed blocked track at its default volume.
            self.event?(event)
        }
    }
    // Initial connection is announced by connect() completion; don't emit a second one-shot from roomDidConnect.
    nonisolated func room(_ room: Room, didStartReconnectWithMode reconnectMode: ReconnectMode) { notify(room, .reconnecting) }
    nonisolated func room(_ room: Room, didCompleteReconnectWithMode reconnectMode: ReconnectMode) { notify(room, .reconnected) }
    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) { notify(room, .disconnected) }
    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) { notify(room, .participantsChanged) }
    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) { notify(room, .participantsChanged) }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication) { notify(room, .participantsChanged) }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnpublishTrack publication: RemoteTrackPublication) { notify(room, .participantsChanged) }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) { notify(room, .participantsChanged) }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) { notify(room, .snapshot) }
    nonisolated func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) { notify(room, .snapshot) }
    nonisolated func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) { notify(room, .snapshot) }
    nonisolated func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) { notify(room, .snapshot) }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, trackPublication: RemoteTrackPublication, didUpdateIsSubscriptionAllowed isSubscriptionAllowed: Bool) { notify(room, .snapshot) }
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) { notify(room, .snapshot) }
}
