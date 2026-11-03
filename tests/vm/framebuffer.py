"""Read the virtual GPU through QEMU's private UNIX VNC socket. No input APIs."""
import socket
import struct
import time
import zlib
from pathlib import Path


class Frame:
    def __init__(self, width, height):
        self.width, self.height = width, height
        self.pixels = bytearray(width * height * 3)
        self.covered = bytearray(width * height)

    def paste(self, x, y, width, height, data):
        for row in range(height):
            for col in range(width):
                source = (row * width + col) * 4
                target = (y + row) * self.width + x + col
                self.pixels[target * 3:target * 3 + 3] = data[source:source + 3][::-1]
                self.covered[target] = 1

    def getdata(self):
        return (tuple(self.pixels[n:n + 3]) for n in range(0, len(self.pixels), 3))

    def save(self, path):
        def chunk(kind, data):
            return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
        rows = b"".join(b"\0" + self.pixels[n:n + self.width * 3] for n in range(0, len(self.pixels), self.width * 3))
        Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))

    def __enter__(self): return self
    def __exit__(self, *args): pass


def capture(path, accept=None, rejected_path=None):
    # This reader serves controlled lab fixtures. Neither QEMU's inactive text
    # nor a blank compositor frame contains their green/blue background pixels.
    if accept is None:
        accept = lambda frame: sum(1 for rgb in frame.getdata() if rgb in ((0, 255, 17), (26, 27, 38))) >= 1000
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(12)
        connection.connect(str(path))
        def read(size):
            if size > 32 * 1024 * 1024: raise RuntimeError('Oversized virtual framebuffer message')
            data = bytearray()
            while len(data) < size:
                chunk = connection.recv(size - len(data))
                if not chunk: raise RuntimeError('Virtual framebuffer disconnected')
                data.extend(chunk)
            return bytes(data)
        if not read(12).startswith(b'RFB 003.'): raise RuntimeError('Unknown virtual framebuffer protocol')
        connection.sendall(b'RFB 003.008\n')
        count = read(1)[0]
        if not count or 1 not in read(count): raise RuntimeError('Private virtual framebuffer authentication unavailable')
        connection.sendall(b'\x01')
        if struct.unpack('!I', read(4))[0]: raise RuntimeError('Private virtual framebuffer rejected connection')
        connection.sendall(b'\x01')
        width, height = struct.unpack('!HH', read(4))
        read(16)
        read(struct.unpack('!I', read(4))[0])
        if not width or not height or width * height > 8 * 1024 * 1024:
            raise RuntimeError('Unexpected virtual framebuffer size')
        # Little-endian 32bpp true color. Only raw rectangles and resize notifications.
        connection.sendall(b'\0\0\0\0' + struct.pack('!BBBBHHHBBB3x', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
        connection.sendall(struct.pack('!BBHii', 2, 0, 2, 0, -223))
        picture = Frame(width, height)
        end = time.monotonic() + 15
        while time.monotonic() < end:
            connection.sendall(struct.pack('!BBHHHH', 3, 0, 0, 0, width, height))
            kind = read(1)[0]
            if kind == 2: continue  # bell
            if kind == 3:
                read(3); read(struct.unpack('!I', read(4))[0]); continue
            if kind != 0: raise RuntimeError('Unexpected virtual framebuffer message')
            read(1)
            rectangles = struct.unpack('!H', read(2))[0]
            for _ in range(rectangles):
                x, y, w, h, encoding = struct.unpack('!HHHHi', read(12))
                if encoding == -223:
                    width, height = w, h
                    if not w or not h or w * h > 8 * 1024 * 1024: raise RuntimeError('Oversized virtual framebuffer')
                    picture = Frame(w, h)
                elif encoding == 0:
                    if x + w > width or y + h > height: raise RuntimeError('Invalid virtual framebuffer rectangle')
                    picture.paste(x, y, w, h, read(w * h * 4))
                else: raise RuntimeError('Unsupported virtual framebuffer encoding')
            if all(picture.covered) and (accept is None or accept(picture)): return picture
            if rejected_path is not None: picture.save(rejected_path)
        raise RuntimeError('Virtual framebuffer did not provide a complete frame')
