#!/usr/bin/env python3
"""Android TV Remote Protocol v2 PoC — pair, send keys, launch deep links.

Usage:
    python poc/remote_poc.py <TV_IP> [API_PORT]

API_PORT defaults to 6466. Pass another port to go through a proxy such as
mitmproxy (see poc/mitm/README.md).

Flow:
  1. Generate a client certificate (certs/cert.pem, certs/key.pem) if missing.
  2. Try to connect. If the TV doesn't know our cert, start pairing:
     a 6-digit code appears on the TV screen — type it in here.
  3. Reconnect with the paired certificate.
  4. Interactive prompt for key commands and deep-link app launches.

Commands at the prompt:
  key <KEYCODE>   e.g. key DPAD_UP / key DPAD_CENTER / key BACK
  home            shortcut for key HOME
  power           shortcut for key POWER
  app <url>       launch deep link, e.g. app https://tver.jp/episodes/xxxx
  tver <url|id>   launch TVer episode (accepts full URL or episode id)
  info            show device info / power state / current app
  quit            exit
"""
import asyncio
import pathlib
import sys

from androidtvremote2 import (
    AndroidTVRemote,
    CannotConnect,
    ConnectionClosed,
    InvalidAuth,
)

CERT_DIR = pathlib.Path(__file__).resolve().parent.parent / "certs"
CLIENT_NAME = "atv-remote-poc"


async def ainput(prompt: str) -> str:
    return await asyncio.to_thread(input, prompt)


async def pair(remote: AndroidTVRemote) -> None:
    print("Starting pairing — a 6-digit code should appear on the TV screen.")
    await remote.async_start_pairing()
    while True:
        code = (await ainput("Enter the 6-digit code shown on the TV: ")).strip()
        try:
            await remote.async_finish_pairing(code)
            print("Pairing succeeded.")
            return
        except InvalidAuth:
            print("Wrong code, try again (pairing restarted).")
            await remote.async_start_pairing()
        except ConnectionClosed:
            print("TV closed the connection; restarting pairing.")
            await remote.async_start_pairing()


async def connect(remote: AndroidTVRemote) -> None:
    """Connect, pairing first if the TV doesn't trust our certificate."""
    while True:
        try:
            await remote.async_connect()
            return
        except InvalidAuth:
            await pair(remote)
        except (CannotConnect, ConnectionClosed) as exc:
            sys.exit(f"Cannot connect to {remote.host}: {exc}")


def tver_url(arg: str) -> str:
    if arg.startswith(("http://", "https://")):
        return arg
    return f"https://tver.jp/episodes/{arg}"


async def repl(remote: AndroidTVRemote) -> None:
    print("\nConnected. Type 'help' for commands, 'quit' to exit.")
    while True:
        try:
            line = (await ainput("atv> ")).strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        cmd, _, arg = line.partition(" ")
        cmd = cmd.lower()
        arg = arg.strip()
        try:
            if cmd == "quit":
                break
            elif cmd == "help":
                print(__doc__)
            elif cmd == "key" and arg:
                remote.send_key_command(arg.upper())
                print(f"sent {arg.upper()}")
            elif cmd == "home":
                remote.send_key_command("HOME")
                print("sent HOME")
            elif cmd == "power":
                remote.send_key_command("POWER")
                print("sent POWER")
            elif cmd == "app" and arg:
                remote.send_launch_app_command(arg)
                print(f"launched {arg}")
            elif cmd == "tver" and arg:
                url = tver_url(arg)
                remote.send_launch_app_command(url)
                print(f"launched {url}")
            elif cmd == "info":
                print(f"device_info: {remote.device_info}")
                print(f"is_on: {remote.is_on}")
                print(f"current_app: {remote.current_app}")
            else:
                print("unknown command; type 'help'")
        except ConnectionClosed:
            print("Connection lost; reconnecting...")
            await connect(remote)


async def main() -> None:
    if len(sys.argv) not in (2, 3):
        sys.exit(f"Usage: {sys.argv[0]} <TV_IP> [API_PORT]")
    host = sys.argv[1]
    api_port = int(sys.argv[2]) if len(sys.argv) == 3 else 6466

    CERT_DIR.mkdir(exist_ok=True)
    remote = AndroidTVRemote(
        client_name=CLIENT_NAME,
        certfile=str(CERT_DIR / "cert.pem"),
        keyfile=str(CERT_DIR / "key.pem"),
        host=host,
        api_port=api_port,
    )
    if await remote.async_generate_cert_if_missing():
        print(f"Generated new client certificate in {CERT_DIR}/")

    await connect(remote)
    remote.keep_reconnecting()

    name, version = remote.device_info["model"], remote.device_info.get("sw_version")
    print(f"Paired & connected to {name} (sw {version}) at {host}")

    try:
        await repl(remote)
    finally:
        remote.disconnect()
        print("Disconnected.")


if __name__ == "__main__":
    asyncio.run(main())
