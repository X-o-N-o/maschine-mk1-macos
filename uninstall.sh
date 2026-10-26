#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Removes MK1 Bridge. Your mapping (~/.config/mk1-midi/config.json) is kept
# unless you pass --purge.
set -euo pipefail

pkill -x MK1Bridge 2>/dev/null || true
sleep 2
rm -rf "$HOME/Applications/MK1 Bridge.app" \
       "$HOME/Library/Application Support/MK1Bridge" \
       "$HOME/Library/Logs/MK1Bridge"
if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$HOME/.config/mk1-midi"
  echo "Removed MK1 Bridge and its configuration."
else
  echo "Removed MK1 Bridge (configuration kept in ~/.config/mk1-midi)."
fi
echo "If you enabled 'Start at Login', macOS drops the login item once the app is gone."
echo "Homebrew packages (libusb, python@3.12) were left installed."
