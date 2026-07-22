#!/usr/bin/env python3
"""Minimal HTTP Upgrade to TCP relay for SSH payloads.
Not a RFC6455 frame proxy: intended for SSH injector-style HTTP upgrade clients.
"""
import asyncio, os
HOST=os.getenv('LISTEN_HOST','0.0.0.0')
PORT=int(os.getenv('LISTEN_PORT','80'))
TARGET_HOST=os.getenv('TARGET_HOST','127.0.0.1')
TARGET_PORT=int(os.getenv('TARGET_PORT','22'))

async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data); await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        try: writer.close(); await writer.wait_closed()
        except Exception: pass

async def handle(reader, writer):
    try:
        head=await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'),10)
        if len(head)>65536: raise ValueError('header too large')
        tr,tw=await asyncio.open_connection(TARGET_HOST,TARGET_PORT)
        writer.write(b'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n')
        await writer.drain()
        await asyncio.gather(pipe(reader,tw),pipe(tr,writer))
    except Exception:
        try: writer.write(b'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'); await writer.drain()
        except Exception: pass
        writer.close()

async def main():
    srv=await asyncio.start_server(handle,HOST,PORT,reuse_address=True)
    async with srv: await srv.serve_forever()

if __name__=='__main__': asyncio.run(main())
