# atv-remote

[日本語](README.md) | English

A from-scratch implementation of the Android TV Remote Protocol v2. Discovers and pairs with Android TVs on your LAN, sends key presses, and launches apps by URL (e.g. TVer).

| Directory | Contents |
|---|---|
| `ATVRemoteKit/` | Swift implementation + CLI |
| `ios/ATVRemote/` | iOS app |
| `android/` | Kotlin implementation + Android app (not yet tested on a real TV) |
| `poc/` | Python PoC |

## Usage

```bash
cd ATVRemoteKit
swift run atvremote-cli discover     # find TVs
swift run atvremote-cli <TV IP>      # pair -> control
```

## CI vs. local verification

CI runs only `swiftlint` and `android`. Verify the Swift package and iOS app locally before pushing (commands in [CLAUDE.md](CLAUDE.md)).

## License

MIT
