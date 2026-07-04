#!/usr/bin/env python3
"""Discover Android TV Remote Protocol v2 devices on the LAN via mDNS.

Browses for _androidtvremote2._tcp services and prints each device's
name, IP address and port. Runs for --timeout seconds (default 10).
"""
import argparse
import asyncio

from zeroconf import ServiceStateChange, Zeroconf
from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf

SERVICE_TYPE = "_androidtvremote2._tcp.local."


async def main(timeout: float) -> None:
    found: dict[str, dict] = {}
    aiozc = AsyncZeroconf()
    pending: set[asyncio.Task] = set()

    def on_change(
        zeroconf: Zeroconf,
        service_type: str,
        name: str,
        state_change: ServiceStateChange,
    ) -> None:
        if state_change is not ServiceStateChange.Added:
            return
        task = asyncio.ensure_future(resolve(name))
        pending.add(task)
        task.add_done_callback(pending.discard)

    async def resolve(name: str) -> None:
        info = AsyncServiceInfo(SERVICE_TYPE, name)
        if await info.async_request(aiozc.zeroconf, 3000):
            addresses = info.parsed_scoped_addresses()
            found[name] = {
                "name": name.removesuffix("." + SERVICE_TYPE),
                "addresses": addresses,
                "port": info.port,
            }
            print(
                f"  [found] {found[name]['name']}  "
                f"ip={', '.join(addresses)}  port={info.port}"
            )

    print(f"Browsing for {SERVICE_TYPE} ({timeout:.0f}s)...")
    browser = AsyncServiceBrowser(aiozc.zeroconf, SERVICE_TYPE, handlers=[on_change])
    await asyncio.sleep(timeout)
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)
    await browser.async_cancel()
    await aiozc.async_close()

    print()
    if not found:
        print("No devices found.")
        return
    print(f"=== {len(found)} device(s) found ===")
    for dev in found.values():
        print(f"  {dev['name']}: {', '.join(dev['addresses'])}:{dev['port']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()
    asyncio.run(main(args.timeout))
