"""Install the pinned Lune binary used for real Roblox datatype tests."""
from pathlib import Path
import argparse
import hashlib
import io
import os
import subprocess
import tempfile
import urllib.request
import zipfile

VERSION = '0.11.0'
URL = f'https://github.com/lune-org/lune/releases/download/v{VERSION}/lune-{VERSION}-linux-x86_64.zip'
ARCHIVE_SHA256 = '5a0ea32c3e13e5e3b1dc415c2056bcfe44258b3a811dcd473c50e3b437d10f72'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, type=Path)
    args = parser.parse_args()
    # Always validate the official archive before using its executable bytes.
    with urllib.request.urlopen(URL, timeout=60) as response:
        data = response.read(32 * 1024 * 1024 + 1)
    if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('Lune archive checksum mismatch')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if archive.testzip() is not None:
            raise ValueError('Lune archive CRC mismatch')
        binary = archive.read('lune')
    target = args.target.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as file:
        temporary = Path(file.name)
        try:
            file.write(binary)
            file.flush()
            os.fsync(file.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        temporary.chmod(0o755)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    subprocess.run([str(target), '--version'], check=True)


if __name__ == '__main__':
    main()
