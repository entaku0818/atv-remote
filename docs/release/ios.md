# iOS リリース準備

## 販売方式（2026-11-07）

- アプリ名: ポケットリモコン
- Bundle ID: `com.entaku.pocketremote`
- バージョン: 1.0.0 (2)、iOS 17以降、iPhone / iPad、日本語
- アプリ本体を480円で販売。App Store Connectでアプリ本体の価格として設定する。
- 購入後は最初から全機能を利用可能。アプリ内課金・月額料金・購入復元UIなし。
- RevenueCat SDK・購入チェックを撤去。旧RevenueCatプロジェクトは履歴として残すが利用しない。

## Xcodeプロジェクト管理

`ios/ATVRemote/ATVRemote.xcodeproj` をGitで直接管理する。XcodeGenは不要。
ターゲット・ファイル追加・ビルド設定はXcodeで編集し、共有スキームとともにコミットする。
`Info.plist` は直接編集する。ユーザー固有の `xcuserdata` はコミットしない。

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

- 日本でのアプリ価格を480円に設定する。IAP商品は追加しない。
- 更新された有料App契約へのAccount Holderの同意が必要。
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
- TV実機検証、App Store Connect価格設定は未完了。IPAアップロード結果は下記を参照。

ローカルログ: `/tmp/pocketremote-paid-verify.log`、`/tmp/pocketremote-paid-distribution.log`。

## 審査提出準備（2026-11-07）

- Release構成のSimulator用ビルド成功。iPhone 18 Pro MaxとiPad Pro 13インチでホーム画面を撮影。
- LAN上のTV検出を確認。ペアリングとTV操作の実機受け入れは未完了。
- 撮影画像はTVのローカルアドレスを含むため、`build/release-screenshot-drafts/` に確認用として保存（Git管理外・未入稿）。
- 審査用の操作手順を `fastlane/metadata/review_information/notes.txt` に用意。
- サポート原稿を [support-ja.md](support-ja.md) に用意。問い合わせ先が未設定のため未公開。
- App Store Connect登録済み: [ポケットリモコン](https://appstoreconnect.apple.com/apps/6831694414/distribution)、App ID `6831694414`。
- バージョン1.0.0、日本語説明・キーワード・サブタイトル・著作権を保存済み。
- 初回アップロードで画面回転設定不足（90474）を検出。全4方向をInfo.plistに追加し、署名付きArchive・IPA再生成成功。
- 480円の価格設定、公開URL、スクリーンショット、実機受け入れ、審査提出は未完了。

## IPAアップロード（2026-11-07）

- 修正版1.0.0 (2)のアップロード成功: `UPLOAD SUCCEEDED with no errors`。
- Delivery UUID: `eddee20d-e035-4bdd-a960-8a7866b34887`。
- ログ: `/tmp/pocketremote-upload-retry.log`。
- 後続のAPI確認でビルド2は `VALID` / `APP_STORE_ELIGIBLE`。Apple側処理完了。審査には未提出。
- ストアのプライマリカテゴリを `UTILITIES` に保存し、読み戻し確認済み。
- RevenueCatは現在の販売方針の記録のみとユーザー確認済み。有料ダウンロード・追加課金なしを維持し、SDKは再導入しない。

## 提出設定の追加確認（2026-11-07）

- バージョン1.0.0に処理済みビルド2を紐付け、APIで読み戻し確認済み。
- 年齢区分の回答をリモコンアプリの機能に合わせて保存済み。
- 価格のAPI確認では日本は800円（米国基準の自動換算）。合意済み480円への修正が必要。
- 配信地域は未設定（appAvailabilityV2は404）。
- ブラウザは再ログインが必要。問い合わせ先・実機操作結果は未回答、審査未提出。

## 価格・公開ページ・審査情報の登録（2026-11-07）

- 日本の価格を480円に変更。App Store Connect APIのmanualPricesでJPN/customerPrice=480を読み戻し確認済み。
- ユーザー指定により全175か国・地域を配信対象に設定。画面で「アプリのリリース時に配信可能」を確認。日本以外は既存の米国4.99 USD基準の価格設定。
- サポート・プライバシーポリシーをGitHub公開リポジトリで公開し、App Store Connectの各URLに登録済み。
- 公開問い合わせ先は既存Voice Narratorと同じ `entaku19890818@gmail.com`。ユーザーの「他と合わせて」に基づく。
- 審査連絡先は既存アプリと同じ情報を設定、操作手順を登録済み。連絡先の私的情報はこの文書には転記しない。
- 輸出コンプライアンスはOS標準の暗号APIのみとして申告し、ビルドのusesNonExemptEncryption=falseを確認済み。
- アプリのプライバシーは「データ収集なし」を入力済み。最終公開はユーザーが自分で確認して操作すると回答したため、こちらでは実施していない。
- 未完了: 公開用スクリーンショット入稿、TV実機のペアリング・基本操作確認、プライバシー回答の公開確認、契約の最新状態確認、審査提出。
- スクリーンショット: 既存の撮影下書きは未入稿。Xcode DeviceInteractionは専用device-interactionスキルを要求するが現在取得できず、セッションを終了。Native Simulator操作も接続できなかった。
- 審査提出・一般公開はまだ実施していない。

## TVの検出条件を明確化（2026-11-07）

- アプリ内ホーム・接続ガイド、ストア説明、公開サポートページに、TVの電源を入れて同じWi-Fi（ネットワーク）に接続してから検索する手順を明記。
- 電源OFF時にネットワーク接続が切れるTVは、アプリから発見・電源ONできないことを明記。
- App Store Connectの日本語説明は更新・読み戻し確認済み。
- アプリ内文言はソースに反映。アップロード済みビルド2には含まれないため、審査前に新ビルドの作成・アップロードが必要。

## 修正版ビルド3・ストア画像（2026-11-07）

- TVの電源・ネットワーク接続条件を明記した1.0.0 (3)の署名付きArchive/IPAを生成。Archive・Export成功。
- ビルド3のアップロード成功。Delivery UUID: `760712ca-2a2a-4917-b306-310b0916cb39`。
- Apple側の処理状態 `VALID` / `APP_STORE_ELIGIBLE` を確認し、バージョン1.0.0の選択ビルドを2から3へ変更。
- ビルド3の輸出コンプライアンスを `usesNonExemptEncryption=false` に設定。
- ユーザーの最終指示「公開して」に基づき、プライバシー回答「データ収集なし」を公開。画面で公開済みを確認。
- ClipKit・nemuの構成を参考に、実アプリUIの撮影＋見出し・背景・端末枠でストア画像を作成。iPhone/iPad各3枚を入稿済み。
- UI撮影テストはiPhone/iPadとも成功。サンプルTV・接続状態はDebug限定。TV実機の操作検証を行ったものではない。
- 元画像と再生成手順は `scripts/screenshots/`、入稿画像は `ios/ATVRemote/fastlane/screenshots/ja/`。
- 申請チェックでコンテンツ配信権回答と一部画像の処理完了待ちが表示された。配信権回答はユーザー確認待ち。
- 有料アプリ契約は画面上「有効（新規契約が利用可能）」。新規契約の同意は実施していない。

## 審査申請完了（2026-11-07 23:17 JST）

- ユーザー承認に基づき `contentRightsDeclaration=DOES_NOT_USE_THIRD_PARTY_CONTENT` を登録し、APIで読み戻し確認。
- スクリーンショット6枚すべての処理状態 `COMPLETE` を確認。
- バージョン1.0.0（ビルド3）をApp Store審査に提出。画面で「1項目が提出されました」を確認。
- APIで `appStoreState=WAITING_FOR_REVIEW` / `appVersionState=WAITING_FOR_REVIEW` を確認。
- `releaseType=AFTER_APPROVAL`：承認後に自動公開。現在は審査待ちで、まだ一般公開されていない。
- 日本480円、全175か国・地域の配信設定を維持。

## Guideline 2.1への再提出（2026-11-08 16:55 JST）

- Appleから実機動画と追加説明を要求されたため、目的・対象者・利用手順・外部サービス・地域差・第三者コンテンツについて英語の審査メモを登録。
- ユーザー提供の約72秒の画面収録を編集せず、審査専用添付 `PocketRemote-iPhoneAir-iOS27-Build3.mp4` として登録。添付ID: `6a749587-4072-4fe2-931f-ac9bc4d05c64`。処理状態COMPLETEを確認。
- 使用端末iPhone Air、iOS 27、ビルド3はユーザー申告。ペアリング・接続・コマンド操作を録画で確認。
- 起動操作は含まれず起動直後の画面から収録、TV本体は映っていない旨をNotesに明記。ユーザーはこの動画のまま提出することを指定。
- 既存提出 `6e6d50d9-21a0-4d2b-8e79-6df706dfcd15` を再提出。APIで提出とバージョン双方の `WAITING_FOR_REVIEW` を確認。
- バージョン1.0.0 (3)、承認後自動公開を維持。動画は公開リポジトリには追加していない。
