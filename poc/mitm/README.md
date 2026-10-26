# mitmproxyでリモート通信（port 6466）を覗く

クライアント（`poc/remote_poc.py`）とAndroid TVの間にmitmproxyをreverseモードで挟み、
TLSを終端して、varint長プレフィックス付きprotobufを `remotemessage.proto` でデコードして
1メッセージ1行で表示する。LTデモ用。

```
remote_poc.py ──TLS──▶ mitmdump 127.0.0.1:16466 ──TLS(ペアリング済みクライアント証明書)──▶ TV:6466
                         └ atv_decode.py が平文を1行ずつ表示
```

## セットアップ（リポジトリ内に閉じたvenv）

```bash
python3 -m venv poc/mitm/.venv            # .gitignoreの .venv/ で無視される
poc/mitm/.venv/bin/pip install mitmproxy protobuf grpcio-tools

# TVに提示するクライアント証明書（Python PoCでペアリング済みのもの）を1ファイルにまとめる
# certs/ は .gitignore 済み。コミットしないこと
cat certs/cert.pem certs/key.pem > certs/mitm-client.pem
chmod 600 certs/mitm-client.pem
```

Pythonのprotobufバインディングは初回起動時に `ios/proto/` から `poc/mitm/gen/`（gitignore済み）へ生成される。

## 実行

ターミナル1（プロキシ）:

```bash
poc/mitm/.venv/bin/mitmdump -q \
  --mode reverse:tls://192.168.0.159:6466@16466 \
  --set client_certs=certs/mitm-client.pem \
  --ssl-insecure \
  -s poc/mitm/atv_decode.py
```

- `reverse:tls://` … TLSを終端し、中身は生TCPとして扱う（HTTPではない）
- `client_certs` … TV側へペアリング済みのクライアント証明書を提示する
- `--ssl-insecure` … TVのサーバ証明書は自己署名なので検証しない
- `-q` … mitmproxy標準のフロー出力を消し、アドオンの行だけを出す

ターミナル2（クライアント）:

```bash
./.venv/bin/python poc/remote_poc.py 127.0.0.1 16466
```

接続するだけで `RemoteConfigure` / `RemoteSetActive` / `RemoteStart` / `RemotePingRequest` /
`RemoteImeKeyInject` が流れる。

> **注意: 以下の出力例は実機ではなく、ローカルの模擬TV（TLSサーバ。6466相当のメッセージを返す）で
> 取得したもの。** 上流ポートが `:26466`、機種が `MOCK-TV` なのはそのため。実機（192.168.0.159）
> での確認、およびペアリング（6467）中継の挙動はまだ確認していない。

出力例（模擬TV）:

```
09:33:16.900 :26466 TV→C RemoteConfigure {code1: 622 device_info { model: "MOCK-TV" vendor: "Mock" app_version: "1.0" }}
09:33:16.900 :26466 C→TV RemoteConfigure {code1: 614 device_info { unknown1: 1 unknown2: "1" package_name: "atvremote" app_version: "1.0.0" }}
09:33:16.901 :26466 TV→C RemoteSetActive {}
09:33:16.901 :26466 TV→C RemoteStart {started: true}
09:33:16.901 :26466 C→TV RemoteSetActive {active: 614}
09:33:17.224 :26466 TV→C RemoteImeKeyInject {app_info { app_package: "com.example.home" }}
09:33:17.249 :26466 TV→C RemotePingRequest {val1: 7}
09:33:17.250 :26466 C→TV RemotePingResponse {val1: 7}
09:33:20.737 :26466 C→TV RemoteKeyInject {key_code: KEYCODE_HOME direction: SHORT}
```

## 注意

- クライアントのホストを `127.0.0.1` にしているので、万一 `remote_poc.py` がペアリングに
  フォールバックしても接続先は `127.0.0.1:6467`（何も待ち受けていない）になり、TVには届かない。
- ペアリング（6467）は中継できない想定: `Secret` はクライアントとサーバの公開鍵から計算されるため、
  mitmproxyが間に入るとクライアントが見る「サーバ公開鍵」がmitmproxyのものになり、TVの計算と一致しない。
