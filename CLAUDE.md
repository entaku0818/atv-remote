# atv-remote

Android TV Remote Protocol v2 の PoC と、iOS/Androidリモコンアプリ化プロジェクト。

## Common Commands

- Lint (SwiftLint): `swiftlint lint`
- Swift package build/test: `cd ATVRemoteKit && swift build && swift test`
- iOS app build: `cd ios/ATVRemote && xcodegen generate && xcodebuild build -project ATVRemote.xcodeproj -scheme ATVRemote -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Android unit test: `cd android && ./gradlew :atvremotekit:test`
- Android cli compile: `cd android && ./gradlew :cli:compileKotlin`
- Android app lint: `cd android && ./gradlew :app:lintDebug`
- Android app assemble: `cd android && ./gradlew :app:assembleDebug`

## ループ運用（Loop Engineering）

このリポジトリは memo リポジトリのプロダクトループ（企画→開発→リリース→効果測定→再企画）の対象。
ここで働くエージェントは以下の規律に従う。

### 起点
- 実装するのは**ユーザーが起票した issue、または `loop-go` ラベル付き issue のみ**。勝手に仕事を選ばない
- 提案がある場合は実装せず、issue コメントか報告として出す

### ハーネス（検証ゲート）
- 実装は build / test / lint が緑になるまで自己修正する（コマンド: `swiftlint lint` / `cd ATVRemoteKit && swift build && swift test` / `cd ios/ATVRemote && xcodegen generate && xcodebuild build -project ATVRemote.xcodeproj -scheme ATVRemote -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO` / `cd android && ./gradlew :atvremotekit:test :cli:compileKotlin :app:lintDebug :app:assembleDebug`）
- **緑でない変更を main に入れない**。5回で緑にならなければブランチに残して報告
- 完了報告には実行した検証コマンドと実出力を含める（「たぶん動く」は完了ではない）

### エスカレーション（諦め方の設計）
- 同一 issue に2回挑戦して解けない → `loop-attempted` ラベルを付けて人間へ
- スコープが当初依頼から拡大しそう → 黙って続けず「続けると+N時間 / 切り出すと今すぐ完了」の2択を提示
- 製品挙動の判断（仕様の分かれ道）に当たった → 勝手に決めず、選択肢と推奨を添えて人間へ

### タイムボックス
- 軽微修正30分・機能実装2時間が目安。超える見込みなら途中で現状報告し分割を提案する
- 深い修理（テストスイート全体・インフラ）は issue 化して夜間ループに回すのがデフォルト

### 記録（Persistence）
- 非自明な発見・設計判断は issue かコミットメッセージに残す（次のエージェントの Discovery 入力になる）
- 機能リリース時は対応する提案の「答え合わせキー」をリリースノートに含める（リリース+7日で memo のループが KPI 答え合わせをする）
