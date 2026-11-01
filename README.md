# atv-remote

日本語 | [English](README.en.md)

Android TV Remote Protocol v2 の自前実装。LAN内のAndroid TVを発見・ペアリングし、キー送信とURL起動（TVer等）ができる。

| ディレクトリ | 内容 |
|---|---|
| `ATVRemoteKit/` | Swift実装 ＋ CLI |
| `ios/ATVRemote/` | iOSアプリ |
| `android/` | Kotlin実装 ＋ Androidアプリ（実機未検証） |
| `poc/` | Python PoC |

## 使い方

```bash
cd ATVRemoteKit
swift run atvremote-cli discover     # TVを探す
swift run atvremote-cli <TVのIP>     # ペアリング → 操作
```

## CIとローカル検証の分担

CIは `swiftlint` と `android` のみ。Swift package と iOSアプリは push 前にローカルで確認する（コマンドは [CLAUDE.md](CLAUDE.md)）。

## License

MIT

## iOS製品版の作業

接続ガイド・IP入力・StoreKit 2買い切り課金・購入復元・プライバシー説明を追加しています。
検証手順と公開前に必要な実機確認・ストア設定は [iOSリリース準備](docs/release/ios.md) を参照してください。

```sh
./scripts/verify-ios.sh 'platform=iOS Simulator,name=iPhone 18 Pro'
```

シミュレータのKeychainテストにはアドホック署名を使用します。生成するReleaseアーカイブは未署名で、ストアには送信しません。
