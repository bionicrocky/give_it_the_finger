#!/bin/zsh
# Install Touch ID for sudo in iTerm2 only when a Touch ID Magic Keyboard is connected.
# Backs up every file it touches with .bak.<timestamp> and records a manifest for clean backout.

set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
INSTALL_DIR="$HOME/.local/share/touchid-sudo-iterm2"
MANIFEST="$INSTALL_DIR/manifest.$TS"
PAM_SUDO="/etc/pam.d/sudo"
BIN_DIR="$HOME/bin"
SUDO_WRAPPER="$BIN_DIR/sudo"
ZSHRC="$HOME/.zshrc"

mkdir -p "$INSTALL_DIR"
: > "$MANIFEST"

note() { printf '%s\n' "$*"; }
record() { printf '%s\t%s\n' "$1" "$2" >> "$MANIFEST"; }  # type<TAB>path

# 1) Backup and ensure pam_tid.so is present in /etc/pam.d/sudo
note "Backing up and enabling Touch ID in $PAM_SUDO..."
sudo cp "$PAM_SUDO" "${PAM_SUDO}.bak.${TS}"
record "backup" "${PAM_SUDO}.bak.${TS}"

if ! grep -q 'pam_tid\.so' "$PAM_SUDO"; then
  tmp="$(mktemp)"
  # Insert pam_tid.so as the first non-comment line
  awk 'BEGIN{ins=0}
       /^#/ && ins==0{print; next}
       ins==0{print "auth       sufficient     pam_tid.so"; ins=1}
       {print}
       END{if(ins==0) print "auth       sufficient     pam_tid.so"}' \
       "$PAM_SUDO" > "$tmp"
  sudo cp "$tmp" "$PAM_SUDO"
  rm -f "$tmp"
  record "modified" "$PAM_SUDO"
else
  note "pam_tid.so already present; leaving $PAM_SUDO content unchanged (backup still created)."
fi

# 2) Create ~/bin and install sudo wrapper (backup any existing one)
note "Installing conditional sudo wrapper at $SUDO_WRAPPER..."
mkdir -p "$BIN_DIR"

if [[ -f "$SUDO_WRAPPER" ]]; then
  cp "$SUDO_WRAPPER" "${SUDO_WRAPPER}.bak.${TS}"
  record "backup" "${SUDO_WRAPPER}.bak.${TS}"
fi

cat > "$SUDO_WRAPPER" <<'ZWRAP'
#!/bin/zsh
# iTerm2-scoped sudo wrapper that prefers Touch ID only when a Touch ID Magic Keyboard is connected.

set -euo pipefail

is_iterm2() {
  [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]
}

has_touchid_keyboard() {
  # Bluetooth: look for Magic Keyboard with Touch ID entries that are connected
  if system_profiler SPBluetoothDataType 2>/dev/null | \
       awk 'BEGIN{IGNORECASE=1}
            /Magic Keyboard with Touch ID( and Numeric Keypad)?/ {seen=1}
            /Connected: Yes/ && seen {connected=1}
            /^$/{ if(connected){print "YES"; exit} seen=connected=0 }' | grep -q YES; then
    return 0
  fi
  # USB: wired usage
  if system_profiler SPUSBDataType 2>/dev/null | \
       grep -Ei 'Magic Keyboard with Touch ID( and Numeric Keypad)?' >/dev/null; then
    return 0
  fi
  return 1
}

if is_iterm2 && has_touchid_keyboard; then
  exec /usr/bin/sudo "$@"
else
  exec /usr/bin/sudo "$@"
fi
ZWRAP

chmod +x "$SUDO_WRAPPER"
record "created" "$SUDO_WRAPPER"

# 3) Ensure ~/bin is in PATH via ~/.zshrc (backup before edit)
ensure_path_line='export PATH="$HOME/bin:$PATH"'
if ! print -r -- "$PATH" | tr ':' '\n' | grep -qx "$HOME/bin"; then
  note "Ensuring $HOME/bin precedes PATH in $ZSHRC..."
  if [[ -f "$ZSHRC" ]]; then
    cp "$ZSHRC" "${ZSHRC}.bak.${TS}"
    record "backup" "${ZSHRC}.bak.${TS}"
  else
    # Touch to create, then back it up empty for symmetry
    : > "$ZSHRC"
    cp "$ZSHRC" "${ZSHRC}.bak.${TS}"
    record "backup" "${ZSHRC}.bak.${TS}"
  fi
  # Only append if not already present
  if ! grep -Fxq "$ensure_path_line" "$ZSHRC"; then
    printf '\n%s\n' "$ensure_path_line" >> "$ZSHRC"
    record "modified" "$ZSHRC"
  fi
else
  note "~/bin already on PATH in current shell; no edit to $ZSHRC."
fi

# 4) Save a copy of the wrapper and metadata for reference
cp "$SUDO_WRAPPER" "$INSTALL_DIR/sudo.wrapper.$TS"
record "created" "$INSTALL_DIR/sudo.wrapper.$TS"
note "Install complete.
Manifest: $MANIFEST

Open a new iTerm2 session or 'source ~/.zshrc' to pick up PATH changes.
Behavior:
- In iTerm2 with a Touch ID Magic Keyboard connected: sudo will allow Touch ID.
- Otherwise: sudo falls back to password."
