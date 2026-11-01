# iOS リリース準備

## 設定

- アプリ名: ATV Remote（既存名を継続、公開前に確定）
- Bundle ID: `com.entaku.atvremote`（既存設定を継続、App Store Connectとの一致を確認）
- 対象: iOS 17以降、iPhone / iPad、日本語
- バージョン: 1.0.0 (1)
- 買い切り Product ID: `com.entaku.atvremote.fullunlock`
- 商品タイプ: Non-Consumable（非消耗型）、希望価格480円
- アプリ画面の価格はStoreKitの`displayPrice`を使用。実際の価格・販売地域はApp Store Connectで設定する。
- 無料機能案: TV検出、IP直接接続、ペアリング、方向キー、決定、戻る。
- 購入で解除する機能案: ホーム、音量、消音、電源、URL起動。無料範囲はオーナー確認待ち。
- Androidとの購入共有なし。購入復元には同じApple Accountを使用する。

## ローカル検証

```sh
swift build --package-path ATVRemoteKit
swift test --package-path ATVRemoteKit
swiftlint lint
xcodegen generate --spec ios/ATVRemote/project.yml
xcodebuild test -project ios/ATVRemote/ATVRemote.xcodeproj -scheme ATVRemote \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath ios/ATVRemote/DerivedData -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
xcodebuild archive -project ios/ATVRemote/ATVRemote.xcodeproj -scheme ATVRemote \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath ios/ATVRemote/build/ATVRemote.xcarchive CODE_SIGNING_ALLOWED=NO
```

`Tests/Local.storekit` はローカル課金検証専用。本番商品を作成する設定ではない。
`StoreKitIntegrationTests` はStoreKitTestを使って実際のStoreKit経路で商品取得、購入、返金を確認する。
署名なしArchiveは提出用IPAではない。配布には実際のApple Developer Team・証明書・プロビジョニングが必要。

## 実機受け入れ（必須、未実施）

結果ごとにTV型番、TV OS、Android TV Remote Serviceバージョン、iPhone機種・OS、日時を記録する。

- 物理リモコンなし・TVネットワーク設定済みの状態で、検出→TVコード表示→入力→無料キー操作。
- TV側で承認操作が必要な機種の確認。ネットワーク未設定のTVはこのアプリだけで初期設定できない。
- ローカルネットワーク拒否→設定で許可→検索再試行。
- IP直接接続、誤ったIP、到達しないTV、コード誤入力、連続再試行、画面を戻る。
- Wi-Fi切断、TV再起動、アプリのバックグラウンド復帰、iPhone再起動後の再接続。
- TV証明書の変更を拒否し、再ペアリングのコード確認後にだけ新しい証明書へ更新。
- 音量、消音、ホーム、電源、URL起動の各機能。電源OFF後にネットワークが停止する機種は電源ON不可。
- Sandbox/TestFlightで購入成功・キャンセル・Ask to Buy承認待ち・復元・返金・オフライン購入済み起動。
- iPhone小画面とiPad、横向き、最大Dynamic Type、VoiceOverでの確認。

## 公開前に残る外部設定

1. アプリ名、Bundle ID、Product ID、無料範囲、サポート窓口を確定する。
2. App Store Connectに非消耗型商品を作成し、480円の価格・地域・審査用説明とスクリーンショットを設定する。
3. サポートURLとプライバシーポリシーURLを公開する。原稿は `privacy-ja.md` と `store-ja.md`。
4. App Privacy回答をアプリとSDKの実際の挙動と照合する。`PrivacyInfo.xcprivacy`はUserDefaults理由CA92.1、トラッキングなしを記載。
5. 暗号化輸出コンプライアンスの回答、年齢区分、権利表記を確認する。未確認の免除をInfo.plistに宣言しない。
6. 署名付きArchiveを作り、TestFlightの実機受け入れを通してから審査提出する。

## 実装上の注意

- TV証明書はペアリングコード検証成功後にKeychainへ保存する。既存PoCからの初回更新では再ペアリングが必要。
- 証明書をIPアドレスに関連付けるため、TVのIP変更後は再ペアリングが必要。
- ログ画面はDebug限定。Releaseの統合ログはprivate扱い。URLは送信ログに出力しない。
- 購入権利はStoreKitの検証済み取引から毎回判定し、UserDefaultsの購入フラグは使わない。
- 購入は無料確認後に利用者が明示的に選ぶ。接続成功やURLの再生成功を課金によって保証しない。

## 参照したApple資料

- https://developer.apple.com/documentation/storekit/transaction/currententitlements
- https://developer.apple.com/documentation/storekit/transaction/updates
- https://developer.apple.com/documentation/storekit/verificationresult
- https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype

## 2026-11-02 検証結果

| 検証 | 結果 |
|---|---|
| `swift build --package-path ATVRemoteKit` | 成功 |
| `swift test --package-path ATVRemoteKit` | 12件成功、失敗0件 |
| iPhone 18 Pro / iOS 27.0 のアプリ単体・統合テスト | 18件成功、`TEST SUCCEEDED` |
| iPhone 18 Pro / iOS 27.0 のUIテスト | 設定・プライバシーとIP入力の2件成功 |
| iPad / iOS 27.0 のUIテスト | 上記2件と購入画面の閉じる操作、計3件成功、`TEST SUCCEEDED` |
| `swiftlint lint --no-cache` | 終了コード0、エラー0件、警告33件（主に既存の行長・末尾カンマ等） |
| 実機向けReleaseの署名なしArchive | `ARCHIVE SUCCEEDED` |
| Archive内の構成 | iOS 17以降・iPhone/iPad、バージョン1.0.0 (1)、Bonjour設定、PrivacyInfoとライセンス同梱を確認 |
| テスト専用ファイル | Releaseアプリに.storekit / .xctestが含まれないことを確認 |
| 実LANでのBonjour検索 | 10秒で検出結果なし。ネットワーク権限・TV側状態も影響するため、対応TVが存在しないとは断定しない |

購入テストは本番課金ではなくStoreKitTestを使用。実際のStoreKit商品取得・購入・返金、および
Keychain永続化、未登録／変更済みTV証明書の拒否をシミュレータで確認した。
最初のiPad実行はケース成功後の後処理が待機したため停止し、`-enableCodeCoverage NO`で再実行して正常終了した。

ローカルの詳細ログと接続画面画像: `ios/ATVRemote/build/verification/`（生成物のためGit管理外）。
最終Archive: `ios/ATVRemote/build/ATVRemote.xcarchive`。
Google TV実機操作、実際のApp Store Sandbox/TestFlight、配布署名、審査提出は未実施。
**これらが完了するまで「公開可能」とは判定しない。**
