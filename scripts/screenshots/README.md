# ストアスクリーンショット

ClipKit・nemuの見出し＋端末フレーム構成を参考に、実際のアプリUIをXCTestで撮影して合成する。
画面を描き直すモックViewは使わない。接続先と接続状態のみDebug限定のサンプルデータを使い、
TV実機の接続成功を示す検証記録とは区別する。撮影用コードはReleaseではコンパイルされない。

- iPhone: 1320 × 2868
- iPad: 2048 × 2732
- 各3枚: リモコン、検索、接続ガイド
- `captures/`: XCTestから書き出した未加工のアプリ画面
- `compose.swift`: 背景・見出し・端末枠を付加するAppKitスクリプト
- 出力: `ios/ATVRemote/fastlane/screenshots/ja/`

## 再撮影

`ATVRemoteUITests/ATVRemoteUITests/testStoreScreenshots` をiPhoneとiPadのSimulatorで実行する。
`xcrun xcresulttool export attachments --path <result.xcresult> --output-path <export-dir>`
で出力し、manifest.jsonの画面名に従ってcapturesへコピーする。

## 再生成

リポジトリルートから:

```sh
swiftc scripts/screenshots/compose.swift -o /tmp/pocketremote-compose
for device in iphone ipad; do
  /tmp/pocketremote-compose scripts/screenshots/captures/$device-remote.png ios/ATVRemote/fastlane/screenshots/ja/01-$device-remote.png remote $device
  /tmp/pocketremote-compose scripts/screenshots/captures/$device-home.png ios/ATVRemote/fastlane/screenshots/ja/02-$device-home.png home $device
  /tmp/pocketremote-compose scripts/screenshots/captures/$device-guide.png ios/ATVRemote/fastlane/screenshots/ja/03-$device-guide.png guide $device
done
```
