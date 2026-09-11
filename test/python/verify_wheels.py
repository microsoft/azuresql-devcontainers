"""Checks every file in a wheelhouse against the SHA-256 that pypi.org publishes for it.

Used only when the smoke test downloads wheels from a PyPI mirror (SMOKE_PIP_MIRROR).
Exits non-zero on any file pypi.org doesn't list or whose digest differs.
"""
import hashlib
import json
import pathlib
import sys
import urllib.request

wheelhouse = pathlib.Path(sys.argv[1])
files = sorted(wheelhouse.iterdir())
if not files:
    sys.exit(f"{wheelhouse} is empty")
for path in files:
    name, version = path.name.split("-")[:2]
    with urllib.request.urlopen(f"https://pypi.org/pypi/{name}/{version}/json", timeout=30) as response:
        published = {f["filename"]: f["digests"]["sha256"] for f in json.load(response)["urls"]}
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if published.get(path.name) != actual:
        sys.exit(f"MISMATCH {path.name}: pypi.org {published.get(path.name)}, file {actual}")
    print(f"verified {path.name} {actual}")
print(f"{len(files)} files match pypi.org")
