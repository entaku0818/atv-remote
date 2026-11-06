# 製品化確認メモ

確認日: 2026-11-02 / 対象コミット: a6cf3e7eb705835e5c57c7862c6fc4bcd7e9a9f3

以下の現状表は取得時点の静的確認結果。製品版フォルダでの変更は末尾に記録する。

## 現状

| 領域 | 確認結果 | 根拠 |
|---|---|---|
| iOS | SwiftUIとRemoteViewModel、検出・ペアリング・キー・URL送信あり | ios/ATVRemote/Sources/ |
| iOS鍵保存 | Keychainを利用 | ATVRemoteKit/Sources/ATVRemoteKit/ClientIdentity.swift |
| Android | Compose画面と通信実装あり。READMEでは実機未検証 | android/app/、android/atvremotekit/ |
| Android鍵保存 | key.der / cert.derへ保存。Android Keystore対応が必要 | android/app/src/main/kotlin/app/RemoteViewModel.kt、android/atvremotekit/src/main/kotlin/atvremotekit/ClientIdentity.kt |
| 切断処理 | iOSはonClosedを画面に反映。Android ViewModelは購読していない | 両OSのRemoteViewModel |
| 検出画面 | 未検出時は検索中表示。接続条件や失敗時の案内が不足 | 両OSのDeviceList画面 |
| 課金 | 確認したアプリソース内にStoreKit / BillingClient実装なし | ios/ATVRemote/Sources/、android/app/ |

## 優先する検証

1. **物理リモコンを使わない初回ペアリング**: TVがネットワーク接続済みで画面を確認できる条件で、スマホから検出→TVにコード表示→スマホでコード入力→方向キー・決定・戻るを実施。TV機種、OS、Remote Serviceバージョン、スマホOSを記録する。TV側で承認操作が必要かも記録する。
2. **ネットワーク未設定のTV**: 初期設定済みのTVとは別シナリオ。現在のLAN通信実装で解決できると約束しない。検出不能時の説明を用意する。
3. **Android接続の安定性**: Wi-Fi切断、TV再起動、画面離脱、バックグラウンド復帰、コード誤入力を試す。接続中のまま固まらず、状態を表示して再試行できること。
4. **鍵の永続性**: アプリ再起動・端末再起動後に再接続する。Keystore対応後はTLS接続まで実機で確認する。

## 実装候補

- Androidの切断通知と再接続、処理のキャンセル・タイムアウトを整備する。RemoteSession.connectは接続開始後にstartedDeferredを設定しており、早い応答を取り逃す可能性があるため再現テストを追加する。
- Androidの鍵保存をKeystore対応にし、既存ペアリング情報の移行方針を決める。
- 検出画面に同一ネットワーク・TV画面の確認案内と、見つからない場合の導線を追加する。
- 課金仕様案: 無料で検出・ペアリング・基本キーの動作確認ができ、購入後に制限解除。無料範囲は実装前に決定する。買い切り480円は希望価格として扱い、ストア設定と実際の表示価格を確認する。
- 課金時は購入成功・キャンセル・保留・復元・購入済み再起動を検証する。

## 公開前の完了条件

- 上記実機シナリオを両OSで実施し、機種と結果を記録する。
- CLAUDE.md記載のSwift package、iOS build、SwiftLint、Android test/compile/lint/assembleを通す。
- 接続できない利用者に購入を要求しない導線を確認する。
- ストアの商品設定、購入復元、プライバシー情報、サポート導線を確認する。

この確認ではアプリ実装・ストア設定・公開は変更していない。

## 製品版フォルダでの着手内容（2026-11-02）

元リポジトリを変更せず、`atv-remote-product` にコードをコピーして作業。

- Androidで切断通知をメインスレッドから画面に反映し、再接続ボタンへ戻す。
- 再試行時に古い接続とペアリングを破棄し、画面離脱時に進行中の処理をキャンセルする。
- 接続・ペアリングの応答待ちに15秒の制限を設ける。ブロッキングI/OにはTCP接続・TLSハンドシェイクそれぞれ10秒の制限を設ける。I/O中のキャンセル完了はその終了を待つ場合がある。
- RemoteSessionの待機オブジェクトを通信開始前に登録し、即時応答の取り逃しを修正する。
- 検出画面に同一ネットワーク、TV上のコード、ネットワーク初期設定の案内を追加する。
- 即時応答・即時切断・接続例外・無応答時のキャンセルを確認する4件の回帰テストを追加する。

Keystore対応、課金、iOS変更、実機試験、ストア公開は未実施。

### 検証結果

`android/` で実行:

```sh
ANDROID_HOME=/Users/entaku/Library/Android/sdk ./gradlew -Dorg.gradle.internal.http.connectionTimeout=10000 -Dorg.gradle.internal.http.socketTimeout=10000 :atvremotekit:test :cli:compileKotlin :app:lintDebug :app:assembleDebug
```

実出力: `BUILD SUCCESSFUL in 1m 38s` / `62 actionable tasks: 60 executed, 2 up-to-date`。
単体テストは7件（追加4件）、失敗0件・エラー0件。CLIコンパイル、Android lint、Debug APK生成に成功。
APK: `android/app/build/outputs/apk/debug/app-debug.apk`。
iOS/Swiftコードは変更しておらず、この作業でiOSビルドは実行していない。実機確認は未実施。

## iOS版の更新

上記の静的調査・Android着手時点からiOS実装が進んでいるため、現在のiOS状態は
[リリース準備](docs/release/ios.md) を参照する。
TV証明書照合、通信待ちの上限、接続ガイド、プライバシー情報、テストターゲットを追加。
2026-11-07に有料ダウンロード480円の方式へ変更。RevenueCat・アプリ内課金・無料範囲の制限は撤去。
公開完了を意味するものではなく、Google TV実機・Sandbox/TestFlight・ストア設定は別途必要。
