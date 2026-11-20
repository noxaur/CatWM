#!/bin/sh
set -eu
cd "$(dirname "$0")/Spec"
meta=$(mktemp -d)
trap 'rm -rf "$meta"' EXIT
if [ -n "${TLA2TOOLS:-}" ]; then
    set -- java -XX:+UseParallelGC -cp "$TLA2TOOLS" tlc2.TLC
elif command -v tlc >/dev/null 2>&1; then
    set -- tlc
else
    echo "check-desktop-spec: install the TLA+ tools and put tlc on PATH, or set TLA2TOOLS to tla2tools.jar" >&2
    exit 1
fi
"$@" -workers auto -metadir "$meta" -config DesktopMachine.cfg DesktopMachine.tla
