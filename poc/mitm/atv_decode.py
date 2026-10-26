"""mitmproxy addon: decode Android TV Remote v2 traffic as protobuf, one line per message.

Wire format is [varint length][protobuf bytes] on top of TLS. TCP segments can
split or coalesce messages, so each direction keeps its own reassembly buffer.

Port 6466 (remote) is decoded as remote.RemoteMessage, port 6467 (pairing) as
polo.wire.protobuf.OuterMessage. Python bindings are generated on first load
from ios/proto/ (the single .proto source) into poc/mitm/gen/ (gitignored).

    mitmdump -s poc/mitm/atv_decode.py --mode reverse:tls://192.168.0.159:6466@16466 ...
"""
import datetime
import pathlib
import sys

from google.protobuf import text_format
from mitmproxy import tcp

ROOT = pathlib.Path(__file__).resolve().parent
PROTO_DIR = ROOT.parent.parent / "ios" / "proto"
GEN_DIR = ROOT / "gen"


def _load_protos():
    if not (GEN_DIR / "remotemessage_pb2.py").exists():
        from grpc_tools import protoc

        GEN_DIR.mkdir(exist_ok=True)
        for name in ("remotemessage.proto", "polo.proto"):
            rc = protoc.main(["protoc", f"-I{PROTO_DIR}", f"--python_out={GEN_DIR}", str(PROTO_DIR / name)])
            if rc != 0:
                raise RuntimeError(f"protoc failed for {name}")
    sys.path.insert(0, str(GEN_DIR))
    import polo_pb2
    import remotemessage_pb2

    return remotemessage_pb2.RemoteMessage, polo_pb2.OuterMessage


RemoteMessage, OuterMessage = _load_protos()


def _decode_varint(buf: bytes):
    """Returns (value, consumed) or None if more bytes are needed."""
    result = shift = 0
    for i, byte in enumerate(buf):
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, i + 1
        shift += 7
        if shift > 63:
            raise ValueError("varint too long")
    return None


def _summary(msg) -> str:
    # Show which oneof-like field is set as the message name, e.g.
    # "RemoteKeyInject {key_code: KEYCODE_HOME direction: SHORT}".
    fields = msg.ListFields()
    if isinstance(msg, OuterMessage):
        status = OuterMessage.Status.Name(msg.status) if msg.HasField("status") else "?"
        inner = [(f, v) for f, v in fields if f.name not in ("protocol_version", "status")]
        body = " ".join(f"{v.DESCRIPTOR.name} {{{text_format.MessageToString(v, as_one_line=True)}}}" for f, v in inner)
        return f"[{status}] {body}".rstrip()
    if not fields:
        return "(empty)"
    return " ".join(f"{v.DESCRIPTOR.name} {{{text_format.MessageToString(v, as_one_line=True)}}}" for f, v in fields)


class ATVDecoder:
    def _out(self, flow: tcp.TCPFlow, text: str) -> None:
        ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        port = flow.server_conn.address[1] if flow.server_conn.address else "?"
        print(f"{ts} :{port} {text}", flush=True)

    def tcp_start(self, flow: tcp.TCPFlow):
        flow.metadata["atv_buf"] = {True: b"", False: b""}
        self._out(flow, f"OPEN  client={flow.client_conn.peername} -> tv={flow.server_conn.address}")

    def tcp_message(self, flow: tcp.TCPFlow):
        m = flow.messages[-1]
        bufs = flow.metadata.setdefault("atv_buf", {True: b"", False: b""})
        buf = bufs[m.from_client] + m.content
        port = flow.server_conn.address[1] if flow.server_conn.address else 6466
        cls = OuterMessage if port == 6467 else RemoteMessage
        arrow = "C→TV" if m.from_client else "TV→C"
        while True:
            head = _decode_varint(buf)
            if head is None:
                break
            length, consumed = head
            if len(buf) < consumed + length:
                break
            payload, buf = buf[consumed:consumed + length], buf[consumed + length:]
            try:
                msg = cls.FromString(payload)
                self._out(flow, f"{arrow} {_summary(msg)}")
            except Exception as exc:  # undecodable payload: show raw bytes instead of dropping it
                self._out(flow, f"{arrow} <undecodable {length}B: {exc}> {payload.hex()}")
        bufs[m.from_client] = buf

    def tcp_error(self, flow: tcp.TCPFlow):
        self._out(flow, f"ERROR {flow.error}")

    def tcp_end(self, flow: tcp.TCPFlow):
        self._out(flow, "CLOSE")


addons = [ATVDecoder()]
