"""Independent pixel witness must preserve exact colors and detect partial frames."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('framebuffer', Path(__file__).parent / 'vm/framebuffer.py')
framebuffer = importlib.util.module_from_spec(spec); spec.loader.exec_module(framebuffer)


class VirtualFrame(unittest.TestCase):
    def test_inactive_placeholder_is_skipped_until_actual_fixture_pixels(self):
        width, height = 50, 30
        def update(pixel):
            return b'\0\0' + struct.pack('!H', 1) + struct.pack('!HHHHi', 0, 0, width, height, 0) + pixel * (width * height)
        stream = bytearray(b'RFB 003.008\n\x01\x01' + b'\0' * 4 + struct.pack('!HH', width, height) + b'\0' * 20 +
                           update(b'\0\0\0\0') + update(bytes((38, 27, 26, 0))))
        class Connection:
            requests = []
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def settimeout(self, value): pass
            def connect(self, path): pass
            def sendall(self, data): self.requests.append(data)
            def recv(self, size):
                data = bytes(stream[:size]); del stream[:size]; return data
        connection = Connection()
        with tempfile.TemporaryDirectory() as directory, patch.object(framebuffer.socket, 'socket', return_value=connection):
            rejected = Path(directory) / 'rejected.png'
            frame = framebuffer.capture('/unused-private-socket', rejected_path=rejected)
            self.assertTrue(rejected.read_bytes().startswith(b'\x89PNG'))
        self.assertEqual(set(frame.getdata()), {(26, 27, 38)})
        self.assertEqual(sum(len(request) == 10 and request[0] == 3 for request in connection.requests), 2)

    def test_raw_bgrx_rectangles_and_png_preserve_witness(self):
        frame = framebuffer.Frame(2, 1)
        frame.paste(1, 0, 1, 1, bytes((17, 255, 0, 0)))
        self.assertFalse(all(frame.covered))
        frame.paste(0, 0, 1, 1, bytes((3, 2, 1, 0)))
        self.assertTrue(all(frame.covered))
        self.assertEqual(list(frame.getdata()), [(1, 2, 3), (0, 255, 17)])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'frame.png'; frame.save(path)
            data = path.read_bytes(); self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
            position = 8; compressed = b''
            while position < len(data):
                size = struct.unpack('!I', data[position:position + 4])[0]
                kind = data[position + 4:position + 8]
                payload = data[position + 8:position + 8 + size]
                if kind == b'IDAT': compressed += payload
                position += size + 12
            self.assertEqual(zlib.decompress(compressed), b'\0\x01\x02\x03\x00\xff\x11')
