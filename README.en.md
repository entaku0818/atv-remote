# atv-remote

[日本語](README.md) | English

A from-scratch implementation of the Android TV Remote Protocol v2 (Swift / Kotlin / Python PoC).
It discovers Android TVs on your LAN, pairs with them, sends key presses, and launches apps via deep links (e.g. TVer).

## Layout

| Directory | Contents | Status |
|---|---|---|
| `ATVRemoteKit/` | Swift implementation + `atvremote-cli` | Verified on a real TV |
| `ios/ATVRemote/` | SwiftUI iOS app | Connection and key sending verified on a real device |
| `android/` | Kotlin implementation + CLI + Compose app | Builds and tests only (not yet verified on a real TV) |
| `poc/` | Python PoC (androidtvremote2) | Verified on a real TV |

- Pairing: port 6467 (TLS + self-signed client certificate; enter the 6-digit code shown on the TV)
- Remote: port 6466 (key presses, URL launch via `RemoteAppLinkLaunchRequest`)
- Discovery: mDNS `_androidtvremote2._tcp`
- The source of [androidtvremote2](https://github.com/tronikos/androidtvremote2) serves as the de facto protocol reference

## Usage

```bash
# Swift CLI
cd ATVRemoteKit
swift run atvremote-cli discover        # find TVs
swift run atvremote-cli <TV IP>         # pair -> REPL (key/home/tver/info/quit)

# iOS app
cd ios/ATVRemote && xcodegen generate && open ATVRemote.xcodeproj
```

For the Python PoC, run `pip install androidtvremote2 zeroconf`, then `poc/discover.py` / `poc/remote_poc.py <IP>`.
To inspect the traffic, see [`poc/mitm/README.md`](poc/mitm/README.md).

## CI vs. local verification

CI runs only `swiftlint` and `android` (ubuntu-latest). There are no macOS runners, so
**verify the Swift package and the iOS app locally before pushing.**

```bash
swiftlint lint
cd ATVRemoteKit && swift build && swift test     # Executed 6 tests, with 0 failures
cd ios/ATVRemote && xcodegen generate && xcodebuild build -project ATVRemote.xcodeproj \
  -scheme ATVRemote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
cd android && ./gradlew :atvremotekit:test :cli:compileKotlin :app:lintDebug :app:assembleDebug
```

## Notes

- A TV accepts only one pairing session at a time. If an old process is still running, new connections time out.
- The macOS CLI keeps its key in `~/.atvremote/cli.keychain` (with a random per-machine password) to avoid signing prompts.
- Never commit certificates (`certs/`).

## License

MIT
