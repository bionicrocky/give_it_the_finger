#!/bin/bash
# Test script for conditional Touch ID sudo wrapper in iTerm2.

set -euo pipefail

echo "Checking environment..."
echo "TERM_PROGRAM=${TERM_PROGRAM:-unset}"

# 1. Check if we’re inside iTerm2
if [[ "${TERM_PROGRAM:-}" != "iTerm.app" ]]; then
  echo "⚠️ Not running in iTerm2. Wrapper only applies in iTerm2."
else
  echo "✅ Running in iTerm2."
fi

# 2. Check for Touch ID keyboard
echo
echo "Detecting Touch ID Magic Keyboard..."
if system_profiler SPBluetoothDataType 2>/dev/null | \
     awk 'BEGIN{IGNORECASE=1}
          /Magic Keyboard with Touch ID( and Numeric Keypad)?/ {seen=1}
          /Connected: Yes/ && seen {connected=1}
          /^$/{ if(connected){print "YES"; exit} seen=connected=0 }' | grep -q YES; then
  echo "✅ Touch ID Magic Keyboard detected via Bluetooth."
elif system_profiler SPUSBDataType 2>/dev/null | \
     grep -Ei 'Magic Keyboard with Touch ID( and Numeric Keypad)?' >/dev/null; then
  echo "✅ Touch ID Magic Keyboard detected via USB."
else
  echo "❌ No Touch ID Magic Keyboard detected."
fi

# 3. Run a sudo test
echo
echo "Now testing sudo. If a Touch ID sensor is present, you should be prompted for Touch ID."
echo "Otherwise, you’ll see the standard password prompt."
echo
sudo -v && echo "✅ sudo authentication successful."
