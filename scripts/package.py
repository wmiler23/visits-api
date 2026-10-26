"""Build a deterministic Lambda bundle from src/app.

File order, timestamps and permissions are fixed, so the same source always
produces the same bytes. That makes the SHA-256 printed below a fingerprint of
the code you tested.

Usage: python scripts/package.py dist/app.zip
"""

import hashlib
import sys
import zipfile
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src" / "app"
FIXED_TIME = (1980, 1, 1, 0, 0, 0)  # earliest timestamp the zip format allows


def bundle_files(src=SRC):
    return sorted(
        p
        for p in src.rglob("*")
        if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc"
    )


def build(out, src=SRC):
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w") as zf:
        for path in bundle_files(src):
            info = zipfile.ZipInfo(path.relative_to(src).as_posix(), date_time=FIXED_TIME)
            info.external_attr = 0o644 << 16  # rw-r--r--
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, path.read_bytes())
    return hashlib.sha256(out.read_bytes()).hexdigest()


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    digest = build(argv[1])
    print(f"{argv[1]} sha256={digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
