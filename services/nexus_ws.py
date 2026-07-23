#!/usr/bin/env python3
"""NexusPlus SSH injector proxy.

Compatibility target: SSHPlus-style HTTP Upgrade payloads used by injector
clients. This is intentionally a raw HTTP-upgrade-to-TCP relay, not a full
RFC6455 frame endpoint.
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import logging
import re
from dataclasses import dataclass

LOG = logging.getLogger("nexus-websocket")
MAX_PREAMBLE = 131072
HANDSHAKE_TIMEOUT = 20.0
BUFFER_SIZE = 65536
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


@dataclass(frozen=True)
class Endpoint:
    host: str
    port: int


def parse_endpoint(value: str) -> Endpoint:
    host, sep, port_text = value.rpartition(":")
    if not sep or not host:
        raise argparse.ArgumentTypeError("use HOST:PORT")
    try:
        port = int(port_text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("porta inválida") from exc
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("porta fora do intervalo")
    return Endpoint(host, port)


def next_header_end(data: bytes, start: int = 0) -> tuple[int, int] | None:
    candidates: list[tuple[int, int]] = []
    for marker in (b"\r\n\r\n", b"\n\n"):
        pos = data.find(marker, start)
        if pos >= 0:
            candidates.append((pos, len(marker)))
    return min(candidates) if candidates else None


def looks_like_upgrade(block: bytes) -> bool:
    text = block.decode("latin-1", "ignore").lower()
    return (
        "upgrade:" in text
        or "x-real-host:" in text
        or "x-split:" in text
        or "connection: upgrade" in text
    )


def header_value(block: bytes, name: str) -> str:
    wanted = name.lower()
    text = block.decode("latin-1", "ignore").replace("\r\n", "\n")
    for line in text.split("\n"):
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        if key.strip().lower() == wanted:
            return value.strip()
    return ""


def allowed_target(value: str, default: Endpoint) -> Endpoint:
    """Preserve SSHPlus X-Real-Host compatibility without becoming open proxy."""
    if not value:
        return default
    try:
        candidate = parse_endpoint(value)
    except argparse.ArgumentTypeError:
        return default
    if candidate.host.lower() in {"127.0.0.1", "localhost", "::1"}:
        return candidate
    return default


def handshake_response(block: bytes) -> bytes:
    key = header_value(block, "Sec-WebSocket-Key")
    lines = [
        "HTTP/1.1 101 Switching Protocols",
        "Connection: Upgrade",
        "Upgrade: websocket",
    ]
    if key:
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii", "ignore")).digest()).decode("ascii")
        lines.append(f"Sec-WebSocket-Accept: {accept}")
    return ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")


async def read_injector_preamble(reader: asyncio.StreamReader) -> tuple[bytes, bytes]:
    """Read fragmented LF/CRLF payloads and preserve bytes after the upgrade."""
    data = bytearray()
    scan_from = 0
    complete_blocks = 0

    while len(data) < MAX_PREAMBLE:
        chunk = await asyncio.wait_for(reader.read(BUFFER_SIZE), HANDSHAKE_TIMEOUT)
        if not chunk:
            raise ConnectionError("cliente encerrou antes do upgrade")
        data.extend(chunk)

        while True:
            found = next_header_end(data, scan_from)
            if found is None:
                scan_from = max(0, len(data) - 4)
                break
            pos, marker_len = found
            end = pos + marker_len
            block = bytes(data[:end])
            complete_blocks += 1

            # Injector payloads may send decoy/preliminary requests before the
            # actual Upgrade. Select the first complete block that advertises
            # an upgrade, while tolerating arbitrary HTTP methods and casing.
            if looks_like_upgrade(block):
                return block, bytes(data[end:])

            if complete_blocks >= 16:
                # Legacy SSHPlus accepted nearly any HTTP-looking preamble.
                return block, bytes(data[end:])

            scan_from = end

    raise ValueError("cabeçalho excedeu o limite")


async def relay(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            data = await reader.read(BUFFER_SIZE)
            if not data:
                try:
                    writer.write_eof()
                except (AttributeError, OSError, RuntimeError):
                    pass
                break
            writer.write(data)
            await writer.drain()
    except (asyncio.CancelledError, ConnectionError, BrokenPipeError, OSError):
        pass


async def close_writer(writer: asyncio.StreamWriter | None) -> None:
    if writer is None:
        return
    try:
        writer.close()
        await writer.wait_closed()
    except Exception:
        pass


async def handle_client(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    default_target: Endpoint,
) -> None:
    peer = client_writer.get_extra_info("peername")
    target_writer: asyncio.StreamWriter | None = None
    try:
        block, leftover = await read_injector_preamble(client_reader)
        requested = header_value(block, "X-Real-Host")
        target = allowed_target(requested, default_target)
        method_line = block.decode("latin-1", "ignore").replace("\r", "").split("\n", 1)[0][:200]

        target_reader, target_writer = await asyncio.open_connection(target.host, target.port)
        client_writer.write(handshake_response(block))
        await client_writer.drain()

        if leftover:
            target_writer.write(leftover)
            await target_writer.drain()

        LOG.info("peer=%s request=%r target=%s:%d", peer, method_line, target.host, target.port)

        up = asyncio.create_task(relay(client_reader, target_writer))
        down = asyncio.create_task(relay(target_reader, client_writer))
        done, pending = await asyncio.wait({up, down}, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        await asyncio.gather(*done, *pending, return_exceptions=True)
    except asyncio.TimeoutError:
        LOG.warning("peer=%s timeout no handshake", peer)
    except Exception as exc:
        LOG.warning("peer=%s failed: %s", peer, exc)
        try:
            client_writer.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            await client_writer.drain()
        except Exception:
            pass
    finally:
        await close_writer(target_writer)
        await close_writer(client_writer)


async def main_async(args: argparse.Namespace) -> None:
    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, args.target),
        args.listen.host,
        args.listen.port,
        reuse_address=True,
        limit=MAX_PREAMBLE + BUFFER_SIZE,
    )
    sockets = ", ".join(str(sock.getsockname()) for sock in server.sockets or [])
    LOG.info("listening=%s target=%s:%d", sockets, args.target.host, args.target.port)
    async with server:
        await server.serve_forever()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="NexusPlus SSH injector proxy")
    parser.add_argument("--listen", type=parse_endpoint, default=parse_endpoint("0.0.0.0:80"))
    parser.add_argument("--target", type=parse_endpoint, default=parse_endpoint("127.0.0.1:22"))
    parser.add_argument("--log-level", default="INFO", choices=("DEBUG", "INFO", "WARNING", "ERROR"))
    return parser


def main() -> None:
    args = build_parser().parse_args()
    logging.basicConfig(level=getattr(logging, args.log_level), format="%(asctime)s %(levelname)s %(message)s")
    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
