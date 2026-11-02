# RevenueCat 設定

SDK 5.91.0 を固定。iOS本体の購入・復元・利用権限はRevenueCatで管理します。
既存の独自ペイウォールを使い、商品を直接取得するためOfferingの作成は必須ではありません。

1. RevenueCatに「ポケットリモコン」プロジェクトとApple App Storeアプリを作成します。Bundle IDは `com.entaku.pocketremote`。
2. App Store Connectで非消耗型商品 `com.entaku.pocketremote.fullunlock` を作成し、日本の価格を480円に設定します。
3. RevenueCatのApple接続設定で必要なApp Store Connect認証情報を設定し、商品を登録します。秘密キーはアプリやGitに入れません。
4. Entitlement `full_unlock` を作成し、上の商品を関連付けます。
5. Apple用の公開SDKキー（`appl_...`）を `project.yml` の `REVENUECAT_PUBLIC_API_KEY` に設定し、XcodeGenを再実行します。CIでは同名のxcodebuild引数でも指定できます。公開SDKキーはクライアントに含まれるキーです。秘密APIキーやTest Storeキーは使えません。
6. App Store ConnectのApp Privacyに購入履歴を申告します。用途はアプリ機能と分析。現在の実装は匿名IDのみで、本人特定情報との紐付けや広告トラッキングを行いません。将来の連携追加時は再評価してください。
7. Sandbox/TestFlightで購入・キャンセル・復元・再起動後の解除状態・返金後の解除取り消しを確認し、RevenueCatダッシュボードでも `full_unlock` を確認します。

キー未設定時はSDKを起動せず、無料操作は利用可能、購入は利用不可になります。
公開前にキー設定とSandbox検証が必要です。現状はRevenueCatプロジェクト未作成のためバックエンド疎通は未検証です。

アプリ起動とフォアグラウンド復帰、CustomerInfo更新で権限を確認します。
通信失敗時はメモリ上の直前の状態を維持します。起動直後はRevenueCatが返す権限が確認できるまでロックされます。
匿名IDはSDKが管理し、独自の顧客属性や広告IDを送信しません。

`StoreKitIntegrationTests` はテストターゲットだけのApple StoreKitフィクスチャです。
RevenueCatとの疎通・サーバー検証を保証するものではありません。本体には直接StoreKitで購入するクライアントを含めません。

参考: [iOS SDK](https://www.revenuecat.com/docs/getting-started/installation/ios)、[App Privacy](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy)

## ローカル検証（2026-11-02）

- アプリテスト20件が成功（購入状態、更新通知、復元、未設定キー、通信失敗時の状態維持を含む）。
- xcodebuildは全件成功ログ出力後の終了処理で待機したため中断。コマンドの正常終了とは区別する。
- 署名なしReleaseアーカイブ成功。Bundle IDとRevenueCatライセンス同梱を確認。
- SwiftLint: エラー0、警告33（既存分）。
- RevenueCatプロジェクト未作成・公開SDKキー未設定。RevenueCat/Sandboxの実購入疎通は未検証。
