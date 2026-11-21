#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025 useless-rs
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. This program is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.

HBSS_VERSION="1.0.0"
BASE_URL="${HBSS_BASE_URL:-https://raw.githubusercontent.com/useless-rs/HBSS/main}"
PAYLOAD_SHA256="f32ba5c474ceba878f6f1a7e87768c0708c7b96c0cd9ab55f6065e9fa54c772d"

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/hbss_run.XXXXXX") || { echo "Failed to create temp dir" >&2; exit 1; }
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup 0 1 2 15

PAYLOAD="$WORKDIR/bench.sh"

# Development mode: use a local bench.sh if present (no hash check).
if [ "${HBSS_DEV:-0}" = "1" ] && [ -f "./bench.sh" ]; then
    PAYLOAD="./bench.sh"
else
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required to download the HBSS payload" >&2
        exit 1
    fi
    if ! curl -fsSL --max-time 120 "$BASE_URL/bench.sh" -o "$PAYLOAD"; then
        echo "Failed to download HBSS payload from $BASE_URL/bench.sh" >&2
        exit 1
    fi
    actual=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$PAYLOAD" 2>/dev/null | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$PAYLOAD" 2>/dev/null | awk '{print $1}')
    fi
    if [ -n "$actual" ] && [ "$actual" != "$PAYLOAD_SHA256" ]; then
        echo "HBSS payload checksum mismatch." >&2
        echo "  expected: $PAYLOAD_SHA256" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
fi

sh "$PAYLOAD" "$@"
exit $?