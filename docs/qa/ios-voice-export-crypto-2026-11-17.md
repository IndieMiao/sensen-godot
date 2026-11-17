# Voice integration: microphone purpose and encryption declaration audit (2026-11-17)

SGODOT-387, q(319), compliance audit A7. This records the implementation and the remaining submission decision;
it is not an export-classification approval or an App Store submission.

## Microphone description

Use the exact q(319) approved copy (387 comment `9ba7f67d-ea50-400f-86fc-33295ec697d2`, user bot 783):

- English: `Gensen uses the microphone only for voice chat, while your mic is on. Your voice goes live to people in the same place and isn't recorded.`
- Simplified Chinese: `Gensen 只在语音聊天、你开麦时使用麦克风。你的声音会实时传给同一地点的人，不会被录下来。`

`inject_voice.py` writes NSMicrophoneUsageDescription in the copied Info.plist and en/zh-Hans InfoPlist.strings.
The existing location purpose and other localizations are preserved; running store configuration afterwards must
not erase the microphone key. No background-audio mode, recording, camera permission request or audio data storage
is enabled. The capability remains false, so this build does not request microphone permission at runtime.

## Technical encryption inventory

- Existing HTTPS/WSS signalling and authentication remain. Voice media uses third-party LiveKit/WebRTC DTLS-SRTP;
  it cannot be described simply as encryption confined to Apple's OS.
- This bridge does not configure LiveKit E2EE or a proprietary encryption algorithm; the native capture gate zeros
  outgoing frames in place and is not an encryption/recording feature. No new secret storage or key-distribution
  protocol is introduced. Published SDK binaries are checksum verified.
- The copied project's existing `ITSAppUsesNonExemptEncryption=false` is preserved for this isolated, unsubmitted QA
  build. The injector now preserves an explicit true as well; store-config no longer silently changes true to false.
  Voice injection requires an explicit Boolean declaration rather than inventing one from the presence of a library.

## Official sources checked on 2026-11-17

1. [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
   says the decision includes third-party libraries: false means no encryption or only exempt encryption;
   true means non-exempt encryption. Merely using a standard algorithm is not the complete criterion.
2. [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
   gives OS-provided encryption (for example URLSession HTTPS) as a typically exempt case, and describes
   documentation/self-classification obligations separately.
3. [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
   distinguishes OS-only encryption from industry-standard encryption implemented outside Apple's OS. The current
   table lists a French encryption declaration for the latter, with a footnote that it is required only when
   distributing in France. Proprietary/non-standard encryption has additional documentation requirements.
4. [Determine and upload app encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)
   directs the submission owner through the App Store Connect questionnaire and any required documentation/code.

The retrieved official HTML/DocC JSON and hashes are retained with the 387 build evidence. No store form was edited.

## Remaining before submission

The old A7 note “standard DTLS-SRTP is usually exempt” is insufficient to close the new linked-library decision by
itself. The submission owner / legal-copy owner must confirm the actual country availability (including France)
and App Store Connect questionnaire classification for this SDK configuration, then record the final Boolean and
any required documentation/code. Do not report the QA plist's preserved false as that decision being approved.

This pending classification does not block local Release/UDP validation with voice capability disabled. It does
remain a submission checklist item if the voice SDK is included in the final candidate, even before enabling its UI.
No production key, user password, store upload or release is authorized by this audit.
