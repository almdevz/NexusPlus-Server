#!/usr/bin/env python3
import asyncio
import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).parents[1] / "services" / "nexus_ws.py"
spec = importlib.util.spec_from_file_location("nexus_ws", MODULE_PATH)
ws = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(ws)


class ParserTests(unittest.IsolatedAsyncioTestCase):
    async def parse_fragments(self, fragments):
        reader = asyncio.StreamReader()
        for fragment in fragments:
            reader.feed_data(fragment)
        reader.feed_eof()
        return await ws.read_injector_preamble(reader)

    async def test_lf_payload(self):
        block, leftover = await self.parse_fragments([
            b"GET / HTTP/1.1\nHost: example\nConnection: Upgrade\nUpgrade: websocket\n\nSSH"
        ])
        self.assertIn(b"Upgrade: websocket", block)
        self.assertEqual(leftover, b"SSH")

    async def test_crlf_payload(self):
        block, leftover = await self.parse_fragments([
            b"ACL / HTTP/1.1\r\nHost: example\r\nUpgrade: Websocket\r\n\r\n"
        ])
        self.assertTrue(ws.looks_like_upgrade(block))
        self.assertEqual(leftover, b"")

    async def test_fragmented_payload(self):
        block, leftover = await self.parse_fragments([
            b"PATCH /chat HTTP/1.1\r\nHost: ex",
            b"ample\r\nConnection: Upgrade\r\n",
            b"Upgrade: websocket\r\n\r\nSSH-2.0",
        ])
        self.assertIn(b"PATCH", block)
        self.assertEqual(leftover, b"SSH-2.0")

    async def test_preliminary_request_then_upgrade(self):
        block, leftover = await self.parse_fragments([
            b"GET /cdn-cgi/trace HTTP/1.1\r\nHost: decoy\r\n\r\n",
            b"UNLOCK / HTTP/1.1\r\nHost: real\r\nUpgrade: websocket\r\n\r\nDATA",
        ])
        self.assertIn(b"Upgrade: websocket", block)
        self.assertEqual(leftover, b"DATA")

    def test_loopback_x_real_host_only(self):
        default = ws.Endpoint("127.0.0.1", 22)
        self.assertEqual(ws.allowed_target("localhost:2222", default), ws.Endpoint("localhost", 2222))
        self.assertEqual(ws.allowed_target("8.8.8.8:53", default), default)

    def test_websocket_accept_when_key_present(self):
        block = (
            b"GET / HTTP/1.1\r\n"
            b"Upgrade: websocket\r\n"
            b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        )
        response = ws.handshake_response(block)
        self.assertIn(b"Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", response)


if __name__ == "__main__":
    unittest.main()
