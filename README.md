# Meta Obsidian (iOS)

Native companion app for Meta Ray-Ban Display glasses, using the [Wearables Device Access Toolkit](https://wearables.developer.meta.com/docs/develop/dat/) for camera/microphone access, aiming to write voice-transcribed notes into an Obsidian vault.

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. `cp config.xcconfig.example config.xcconfig` and fill in:
   - `META_APP_ID` / `CLIENT_TOKEN` — from registering an app at the [Wearables Developer Center](https://wearables.developer.meta.com/)
   - `DEVELOPMENT_TEAM` — your Apple Developer Team ID
3. `xcodegen generate`
4. Open `MetaObsidian.xcodeproj` in Xcode

## Status

Scaffold only — builds and links against `MWDATCore`/`MWDATCamera`, with a minimal registration/connection/permission UI. Not yet implemented:

- Microphone capture (raw 8kHz PCM over Bluetooth HFP, no built-in speech-to-text — see `WearablesManager.swift`)
- Whisper API integration for transcription
- Writing transcripts into the Obsidian vault (iCloud Drive file access)

See the `// MARK: - Next steps` comment in `WearablesManager.swift`.
