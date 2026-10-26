#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds "MK1 Bridge.app" for the Native Instruments Maschine MK1 (Apple Silicon, macOS 13+).
#
#   ./build.sh            build into ./build/
#   ./build.sh --install  build, install to ~/Applications and launch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
APP="$OUT/MK1 Bridge.app"
SUPPORT="$HOME/Library/Application Support/MK1Bridge"
VENV="$SUPPORT/venv"
INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "macOS only."
xcode-select -p >/dev/null 2>&1 || fail "Xcode Command Line Tools missing – run: xcode-select --install"
command -v brew >/dev/null || fail "Homebrew missing – see https://brew.sh"

# python-rtmidi ships prebuilt Apple Silicon wheels up to Python 3.12
step "Homebrew: libusb, Python 3.12"
brew install libusb python@3.12
PY="$(brew --prefix python@3.12)/bin/python3.12"
[[ -x "$PY" ]] || fail "Python 3.12 not found ($PY)"

step "Python environment ($VENV)"
mkdir -p "$SUPPORT"
if [[ ! -x "$VENV/bin/python3" ]] || ! "$VENV/bin/python3" -c 'import sys; sys.exit(sys.version_info[:2] != (3, 12))'; then
  rm -rf "$VENV"
  "$PY" -m venv "$VENV"
fi
"$VENV/bin/python3" -m pip install --quiet --upgrade pip
"$VENV/bin/python3" -m pip install --quiet --only-binary=python-rtmidi -r "$ROOT/daemon/requirements.txt"
"$VENV/bin/python3" - <<'EOF'
import usb.core, rtmidi, PIL
print("pyusb", usb.__version__, "| python-rtmidi", rtmidi.__version__, "| Pillow", PIL.__version__)
EOF

step "MK1 Bridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/daemon"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/MK1Bridge" "$ROOT/app/main.swift"
cp "$ROOT/app/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT"/daemon/*.py "$APP/Contents/Resources/daemon/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
codesign --force --sign - "$APP"
echo "Built: $APP"

if [[ $INSTALL -eq 1 ]]; then
  step "Installing to ~/Applications"
  pkill -x MK1Bridge 2>/dev/null || true
  sleep 2
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/MK1 Bridge.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/MK1 Bridge.app"
  echo "MK1 Bridge is running – look for the grid icon in the menu bar."
fi
