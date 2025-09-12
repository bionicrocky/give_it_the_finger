#!/bin/zsh
# Back out the most recent install by restoring backups from the newest manifest.
# You can pass a specific manifest path as $1 to target that install.

set -euo pipefail

INSTALL_DIR="$HOME/.local/share/touchid-sudo-iterm2"
MANIFEST="${1:-}"

if [[ -z "$MANIFEST" ]]; then
  MANIFEST="$(ls -1t "$INSTALL_DIR"/manifest.* 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
  printf 'No manifest found. Nothing to do.\n' >&2
  exit 1
fi

printf 'Using manifest: %s\n' "$MANIFEST"

restore_file() {
  local backup="$1"
  # Original path is the backup path without the trailing ".bak.<timestamp>"
  local orig="${backup%\.bak.*}"
  if [[ -f "$backup" ]]; then
    # If restoring /etc/pam.d/*, use sudo
    if [[ "$orig" == /etc/pam.d/* ]]; then
      sudo cp "$backup" "$orig"
      printf 'Restored (sudo): %s -> %s\n' "$backup" "$orig"
    else
      cp "$backup" "$orig"
      printf 'Restored: %s -> %s\n' "$backup" "$orig"
    fi
  else
    printf 'Backup missing, skipping: %s\n' "$backup" >&2
  fi
}

# Read manifest lines: "<type>\t<path>"
# We restore backups and then optionally remove created files saved under INSTALL_DIR.
while IFS=$'\t' read -r typ path; do
  case "$typ" in
    backup)
      restore_file "$path"
      ;;
    created)
      # Only delete created artifacts under our install dir; leave ~/bin/sudo in place
      # unless there is also a backup we restored above.
      if [[ "$path" == "$INSTALL_DIR/"* ]]; then
        rm -f "$path" && printf 'Removed created artifact: %s\n' "$path"
      fi
      ;;
    modified)
      # Nothing to do here; restoring from backups handles this.
      :
      ;;
    *)
      :
      ;;
  esac
done < "$MANIFEST"

# If we restored a backup of ~/bin/sudo, that copy is now back in place.
# If we did NOT restore one but want to remove our wrapper, uncomment the next block:
# if [[ -f "$HOME/bin/sudo" ]]; then
#   rm -f "$HOME/bin/sudo"
#   printf 'Removed wrapper at %s\n' "$HOME/bin/sudo"
# fi

printf 'Backout complete.\n'
