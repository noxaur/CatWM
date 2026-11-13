#!/usr/bin/env python3
"""Set each tracked file's mtime from its content hash, so a cached .build compiles only what changed.

A fresh checkout gives every file the current time, and the Swift build then recompiles every source
even with a restored .build. A file with the same content gets the same mtime on every machine, and
a changed file gets a different one. CI runs this right after the checkout. The last commit's time
per file would also work, but it needs the full history in every checkout.
"""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EPOCH = 946684800  # 2000-01-01, so every stamp lies in the past

tracked = subprocess.run(["git", "ls-files", "-s", "-z"], cwd=ROOT, capture_output=True, text=True, check=True)
paths = [entry.split("\t", 1)[1] for entry in filter(None, tracked.stdout.split("\0")) if not entry.startswith("160000")]
paths = [path for path in paths if (ROOT / path).is_file() and not (ROOT / path).is_symlink()]
# Hash the working tree, not the index, so a local edit counts as a change too.
blobs = subprocess.run(["git", "hash-object", "--stdin-paths"], cwd=ROOT, input="\n".join(paths),
                       capture_output=True, text=True, check=True).stdout.split()
for path, blob in zip(paths, blobs, strict=True):
    digest = int(blob[:15], 16)
    seconds, nanoseconds = EPOCH + (digest >> 30) % (1 << 28), (digest & ((1 << 30) - 1)) % 1_000_000_000
    stamp = seconds * 1_000_000_000 + nanoseconds
    os.utime(ROOT / path, ns=(stamp, stamp))
