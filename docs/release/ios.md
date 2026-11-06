# iOS リリース準備

## 販売方式（2026-11-07）

- アプリ名: ポケットリモコン
- Bundle ID: `com.entaku.pocketremote`
- バージョン: 1.0.0 (2)、iOS 17以降、iPhone / iPad、日本語
- アプリ本体を480円で販売。App Store Connectでアプリ本体の価格として設定する。
- 購入後は最初から全機能を利用可能。アプリ内課金・月額料金・購入復元UIなし。
- RevenueCat SDK・購入チェックを撤去。旧RevenueCatプロジェクトは履歴として残すが利用しない。

## ローカル検証と配布

```sh
bash scripts/verify-ios.sh
DEVELOPMENT_TEAM=4YZQY4C47E bash scripts/archive-ios.sh
```

検証スクリプトはSwiftLint、Swift packageのビルド・テスト、iOS単体・UIテスト、署名なしRelease Archiveを実行する。
Xcodeのテスト終了時の待機を避けるためカバレッジ収集を無効化している。
配布スクリプトは署名付きArchiveとIPAをローカルに生成する。アップロード・審査提出はしない。
IPA: `ios/ATVRemote/build/distribution/export/ATVRemote.ipa`。

## 公開前の残作業

- App Store Connectにアプリを登録し、日本でのアプリ価格を480円に設定する。IAP商品は追加しない。
- サポートURL、問い合わせ先、プライバシーポリシーURLを用意する。
- ストアスクリーンショット、年齢区分、権利表記、暗号化輸出コンプライアンスを確認する。
- App Privacy回答をSDK撤去後の挙動に合わせる。アプリは購入履歴・匿名顧客IDを送信しない。
- TestFlightで以下の実機受け入れを行ってから審査提出する。

## 実機受け入れ（未完了）

各結果にTV型番・TV OS・Android TV Remote Serviceバージョン・iPhone機種とOS・日時を記録する。

- 同じネットワークでTV検出、TV画面のコードによるペアリング、方向キー・決定・戻る。
- ホーム・音量・消音・電源・URL起動が購入画面なしで利用できること。各操作の対応は機種による。
- ローカルネットワーク拒否後の再許可、直接IP接続、誤IP・誤コード、連続再試行。
- Wi-Fi切断、TV再起動、バックグラウンド復帰、iPhone再起動後の再接続。
- TV証明書の変更を拒否し、再ペアリング後のみ更新すること。
- 小画面・iPad・横向き・最大Dynamic Type・VoiceOver。

TVのネットワーク初期設定をこのアプリだけで行うことはできない。
TVが電源OFF時にネットワーク接続を停止する場合は電源ON操作に対応できない。

## ストア原稿

`ios/ATVRemote/fastlane/metadata/ja/` に入稿用テキスト、
[store-ja.md](store-ja.md) に審査メモ、[privacy-ja.md](privacy-ja.md) にプライバシー原稿を用意。

旧IAP方式の検証結果は [ios-history.md](ios-history.md)、旧RevenueCat設定は [revenuecat.md](revenuecat.md) を参照。

## 有料アプリ方式の検証結果（2026-11-07）

- Swift package: 12件成功。
- iOSアプリ: 9件成功、UI: 2件成功。`** TEST SUCCEEDED **`。
- UIテストで設定画面に購入・復元ボタンが存在しないことを確認。
- SwiftLint: 33 warnings / 0 serious（既存警告）。
- 署名付き配布Archive: `** ARCHIVE SUCCEEDED **`、IPA: `** EXPORT SUCCEEDED **`、終了コード0。
- Archiveのバージョン1.0.0 (2)、RevenueCat公開キー・リソース・StoreKitフィクスチャの未同梱を確認。
- TV実機検証、App Store Connect価格設定、TestFlightアップロードは未実施。

ローカルログ: `/tmp/pocketremote-paid-verify.log`、`/tmp/pocketremote-paid-distribution.log`。

## 審査提出準備（2026-11-07）

- Release構成のSimulator用ビルド成功。iPhone 18 Pro MaxとiPad Pro 13インチでホーム画面を撮影。
- LAN上のTV検出を確認。ペアリングとTV操作の実機受け入れは未完了。
- 撮影画像はTVのローカルアドレスを含むため、`build/release-screenshot-drafts/` に確認用として保存（Git管理外・未入稿）。
- 審査用の操作手順を `fastlane/metadata/review_information/notes.txt` に用意。
- サポート原稿を [support-ja.md](support-ja.md) に用意。問い合わせ先が未設定のため未公開。
- App Store Connectはログアウト状態。アプリ登録・価格設定・IPAアップロード・審査提出は未実施。
