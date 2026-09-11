"""Package the generated PNG representations into a macOS ICNS container."""
from pathlib import Path
import struct
import sys

source, destination = map(Path, sys.argv[1:])
representations = {
    "icp4": "16x16", "ic11": "16x16@2x",
    "icp5": "32x32", "ic12": "32x32@2x",
    "ic07": "128x128", "ic13": "128x128@2x",
    "ic08": "256x256", "ic14": "256x256@2x",
    "ic09": "512x512", "ic10": "512x512@2x",
}
chunks = []
for kind, name in representations.items():
    png = (source / f"icon_{name}.png").read_bytes()
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"Invalid PNG: {name}")
    chunks.append(kind.encode("ascii") + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
destination.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
