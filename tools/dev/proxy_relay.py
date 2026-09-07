#!/usr/bin/env python3
"""把本机回环上的 HTTP 代理（FlClash 默认只听 127.0.0.1:7890）转发到局域网口，给同网段真机用。

真机上的 Godot 不走 iOS 系统代理，Firebase（googleapis）在国内直连不通；客户端读 user://proxy.txt
（host:port）把 HTTPS 请求经这里的 CONNECT 隧道走出去。用法：
    python3 tools/dev/proxy_relay.py [listen_port=7891] [target_port=7890]
只在开发期本机跑，不进任何构建。
"""
import asyncio
import sys

LISTEN = int(sys.argv[1]) if len(sys.argv) > 1 else 7891
TARGET = int(sys.argv[2]) if len(sys.argv) > 2 else 7890


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(cr: asyncio.StreamReader, cw: asyncio.StreamWriter) -> None:
    try:
        tr, tw = await asyncio.open_connection("127.0.0.1", TARGET)
    except Exception as e:
        print(f"target unreachable: {e}", flush=True)
        cw.close()
        return
    await asyncio.gather(pipe(cr, tw), pipe(tr, cw))


async def main() -> None:
    server = await asyncio.start_server(handle, "0.0.0.0", LISTEN)
    print(f"relay 0.0.0.0:{LISTEN} -> 127.0.0.1:{TARGET}", flush=True)
    async with server:
        await server.serve_forever()


asyncio.run(main())
