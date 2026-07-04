# atv-remote

Android TV Remote Protocol v2 の PoC と、iOSリモコンアプリ化プロジェクト。

MacからLAN内のAndroid TVを発見・ペアリングし、キー送信とTVerのdeep link起動まで実機確認済み（Xiaomi MiTV-MOSR4）。

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

## ハマりどころ

- **ペアリングセッションはTVと1本のみ。** 古い `remote_poc.py` プロセスが残っているとTVは古いコードを表示し続け、新プロセスはSSLハンドシェイクで60秒タイムアウトする。`pgrep -f remote_poc.py` で確認して先に殺すこと。
- ペアリングはポート6467、通常接続はポート6466。

## プロトコル概要（iOS実装用メモ）

- TLS + 自己署名クライアント証明書で接続。ペアリングで証明書をTVに登録する
- メッセージはprotobuf（[androidtvremote2](https://github.com/tronikos/androidtvremote2) のソースが実質的な仕様書）
- deep link起動は `RemoteAppLinkLaunchRequest` にURLを載せるだけ（TVerは `https://tver.jp/episodes/...` がそのまま通る）
