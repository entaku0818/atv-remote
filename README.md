# atv-remote

Android TV Remote Protocol v2 の PoC と、iOS/Androidリモコンアプリ化プロジェクト。

MacからLAN内のAndroid TVを発見・ペアリングし、キー送信とTVerのdeep link起動まで実機確認済み（Xiaomi MiTV-MOSR4）。

## 構成

| ディレクトリ | 内容 | 状態 |
|---|---|---|
| `poc/` | Python PoC（androidtvremote2利用） | 実機で全項目動作確認済み |
| `ATVRemoteKit/` | Swiftネイティブ実装（プロトコル自前実装）＋ `atvremote-cli` | 実機で全項目動作確認済み・6単体テストpass |
| `ios/ATVRemote/` | SwiftUI iOSアプリ | シミュレータで起動・mDNS発見確認済み |
| `android/atvremotekit/` | Kotlin/JVMネイティブ実装（プロトコル自前実装）＋ `cli` | 単体テスト・ビルド確認済み（実機ペアリングは未検証） |
| `android/app/` | Jetpack Compose Androidアプリ | ビルド・Lint通過（実機/エミュレータでの動作確認は未実施） |

Swift実装は外部依存が SwiftProtobuf のみ。ペアリング（TLS+自己署名クライアント証明書、
ポート6467）、リモート（ポート6466、キー送信・app link起動）、mDNS発見（NWBrowser）を
`androidtvremote2` のプロトコルに準拠して自前実装している。

Kotlin実装（`android/atvremotekit/`）も同じ設計で、外部依存はprotobuf-javaのみ。JVMの
`RSAPublicKey`がmodulus/exponentを直接`BigInteger`で返すため、Swift版の`ASN1.swift`が
担っていたDERパース（公開鍵の復元）は不要になった一方、自己署名証明書の構築（DERの手組み）
は`ASN1.kt`としてそのまま移植している。`.proto`は`ios/proto/`を単一のソースとして共有し、
Gradleの`protobuf`プラグインから参照している（コピーはしない）。証明書はCLIが
`certs/android/`、Androidアプリが`context.filesDir/atv-remote/`に平文DERで保存する
（true Android Keystoreは今回未使用 — PoCスコープでCLIと鍵生成ロジックを共有するため）。

### Swift CLIでの検証

```bash
cd ATVRemoteKit
swift build                             # ビルド
swift test                              # 単体テスト
swift run atvremote-cli discover        # mDNS発見
swift run atvremote-cli 192.168.0.159   # ペアリング→REPL（key/home/tver/info/quit）
```

macOSのCLIは、ad-hoc署名だとログインキーチェーンが秘密鍵署名のたびにプロンプトを出すため、
`~/.atvremote/cli.keychain`（既知パスワードの専用キーチェーン）を作り partition-list を
開放してプロンプトなしでTLS署名する（`MacKeychainIdentity`）。iOSアプリはアプリスコープの
キーチェーンを使うためこの回避は不要。

### Android/Kotlin CLIでの検証

```bash
cd android
./gradlew :atvremotekit:test           # 単体テスト（ペアリングシークレットはSwift版と同じベクタでクロス検証）
./gradlew :cli:run --args="192.168.0.159"   # ペアリング→REPL（key/home/tver/info/quit）
./gradlew :app:lintDebug                # Android Lint
./gradlew :app:assembleDebug            # APKビルド
```

`:cli:run` はリポジトリ直下で実行したのと同じ状態になるよう作業ディレクトリを固定しており、
証明書は `certs/android/`（Python版の `certs/` と同じ発想）に保存される。

## CIとローカル検証の分担

**GitHub ActionsのmacOSランナーは使わない方針。** macOSランナーはランナーイメージの更新
（`macos-14`のdeprecated化、デフォルトXcodeのバージョン差）でビルドが壊れやすく、
Linuxランナーの数倍のコストがかかるため、macOS/Xcodeを必要とする検証はローカルに寄せている。

| 検証対象 | どこで回すか | コマンド |
|---|---|---|
| SwiftLint | CI（`swiftlint` / ubuntu-latest） | `swiftlint lint` |
| Android（Kotlin実装・アプリ） | CI（`android` / ubuntu-latest） | `cd android && ./gradlew :atvremotekit:test :cli:compileKotlin :app:lintDebug :app:assembleDebug` |
| **ATVRemoteKit（Swift実装）** | **ローカルのみ** | 下記参照 |
| iOSアプリ（`ios/ATVRemote/`） | **ローカル + Xcode Cloud** | 下記参照 |

### ATVRemoteKitのローカル検証（必須）

`ATVRemoteKit/` に触るPRは、pushする前に必ずローカルで以下を実行して緑を確認する。
CIにはこのゲートが無いので、ここを飛ばすと壊れたまま気付かずmainに入る。

```bash
cd ATVRemoteKit
swift build
swift test
```

作業ディレクトリは `ATVRemoteKit/` であることに注意（リポジトリ直下には `Package.swift` が無い）。
期待される結果は6テスト全passで、`Executed 6 tests, with 0 failures` が出れば緑。
PRの説明には実行したコマンドとその出力を貼ること。

### iOSアプリのローカル検証

```bash
cd ios/ATVRemote
xcodegen generate
xcodebuild build \
  -project ATVRemote.xcodeproj \
  -scheme ATVRemote \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

## セットアップ

```bash
git clone https://github.com/entaku0818/atv-remote.git
cd atv-remote
python3 -m venv .venv
./.venv/bin/pip install androidtvremote2 zeroconf
```

## 使い方

### 1. デバイス発見（mDNS）

```bash
./.venv/bin/python poc/discover.py
# => リビングルーム: 192.168.0.159:6466 のようにLAN内のAndroid TVが一覧される
```

### 2. ペアリング〜リモコン操作

```bash
./.venv/bin/python poc/remote_poc.py 192.168.0.159
```

初回はTV画面に6桁コードが表示されるので入力する。証明書が `certs/` に保存され、2回目以降はペアリング不要。

接続後の対話コマンド:

```
key <KEYCODE>   # 例: key DPAD_UP / key DPAD_CENTER / key BACK
home            # ホーム画面へ
power           # 電源
app <url>       # deep link起動
tver <url|id>   # TVerエピソード起動 例: tver https://tver.jp/episodes/ep6ac0d0qy
info            # デバイス情報・電源状態・フォアグラウンドアプリ
quit            # 終了
```

### 動作確認済みフロー

1. `discover.py` でTVのIPを特定
2. `remote_poc.py <IP>` でペアリング（6桁コード入力）
3. `tver https://tver.jp/episodes/xxxx` → TVerアプリが起動し該当エピソードが再生される
4. `key DPAD_CENTER` などでリモコン操作

### 通信を覗く（mitmproxy）

port 6466 の通信をmitmproxyで中継し、protobufをデコードして1行ずつ表示する手順は
[`poc/mitm/README.md`](poc/mitm/README.md) を参照。

## ハマりどころ

- **ペアリングセッションはTVと1本のみ。** 古い `remote_poc.py` プロセスが残っているとTVは古いコードを表示し続け、新プロセスはSSLハンドシェイクで60秒タイムアウトする。`pgrep -f remote_poc.py` で確認して先に殺すこと。
- ペアリングはポート6467、通常接続はポート6466。

## プロトコル概要（iOS実装用メモ）

- TLS + 自己署名クライアント証明書で接続。ペアリングで証明書をTVに登録する
- メッセージはprotobuf（[androidtvremote2](https://github.com/tronikos/androidtvremote2) のソースが実質的な仕様書）
- deep link起動は `RemoteAppLinkLaunchRequest` にURLを載せるだけ（TVerは `https://tver.jp/episodes/...` がそのまま通る）
