# atv-remote

Android TV Remote Protocol v2 を自前実装したリモコン（Swift / Kotlin / Python PoC）。
LAN内のAndroid TVを発見・ペアリングし、キー送信とアプリのdeep link起動（TVer等）ができる。

## 構成

| ディレクトリ | 内容 | 状態 |
|---|---|---|
| `ATVRemoteKit/` | Swift実装 ＋ `atvremote-cli` | 実機確認済み |
| `ios/ATVRemote/` | SwiftUI iOSアプリ | 実機で接続・キー送信確認済み |
| `android/` | Kotlin実装 ＋ CLI ＋ Composeアプリ | ビルド・テストのみ（実機未検証） |
| `poc/` | Python PoC（androidtvremote2） | 実機確認済み |

- ペアリング: ポート6467（TLS＋自己署名クライアント証明書、TVに出る6桁コードを入力）
- リモート: ポート6466（キー送信・`RemoteAppLinkLaunchRequest` でURL起動）
- 発見: mDNS `_androidtvremote2._tcp`
- 仕様は [androidtvremote2](https://github.com/tronikos/androidtvremote2) のソースが実質的なリファレンス

## 使い方

```bash
# Swift CLI
cd ATVRemoteKit
swift run atvremote-cli discover        # TVを探す
swift run atvremote-cli <TVのIP>        # ペアリング → REPL（key/home/tver/info/quit）

# iOSアプリ
cd ios/ATVRemote && xcodegen generate && open ATVRemote.xcodeproj
```

Python PoC は `pip install androidtvremote2 zeroconf` 後に `poc/discover.py` / `poc/remote_poc.py <IP>`。
通信の中身を見るなら [`poc/mitm/README.md`](poc/mitm/README.md)。

## CIとローカル検証の分担

CIは `swiftlint` と `android` のみ（ubuntu-latest）。macOSランナーは使わないので、
**Swift package と iOSアプリはローカルで緑を確認してから push する。**

```bash
swiftlint lint
cd ATVRemoteKit && swift build && swift test     # Executed 6 tests, with 0 failures
cd ios/ATVRemote && xcodegen generate && xcodebuild build -project ATVRemote.xcodeproj \
  -scheme ATVRemote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
cd android && ./gradlew :atvremotekit:test :cli:compileKotlin :app:lintDebug :app:assembleDebug
```

## メモ

- ペアリングセッションはTVと1本だけ。古いプロセスが残っていると新しい接続はタイムアウトする。
- macOS CLIは `~/.atvremote/cli.keychain`（パスワードはマシンごとにランダム生成）に鍵を置き、署名時のプロンプトを避けている。
- 証明書（`certs/`）はコミットしない。

## License

MIT
