import Foundation
import LiveKit

/// LiveKit invokes capturePostProcessingDelegate before encoding/sending microphone audio. This remains attached
/// while retired SDK tasks drain; unlike setMicrophone/engine-availability, closing its gate never calls into RTC.
final class LiveKitCaptureGate: NSObject, AudioCustomProcessingDelegate, @unchecked Sendable {
    let gate = VoiceCaptureGate()
    func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels: Int) {}
    func audioProcessingRelease() {} // Engine restart/reconnect must not reopen a retired gate.
    func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        gate.filter {
            for channel in 0..<audioBuffer.channels {
                audioBuffer.rawBuffer(forChannel: channel).update(repeating: 0, count: audioBuffer.frames)
            }
        }
    }
}
