#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# firefox-nova-islands installer for macOS and Linux.
# https://github.com/matteoninotti/firefox-nova-islands
#
# Usage:
#   ./install.sh                     pick a profile interactively and install
#   ./install.sh --profile <dir>     install into a specific profile folder
#   ./install.sh --uninstall [...]   remove it again
#
# What it does in the chosen profile:
#   1. backs up chrome/userChrome.css and user.js (if present)
#   2. copies nova-islands.css into chrome/
#   3. adds  @import url("nova-islands.css");  to the top of chrome/userChrome.css
#   4. adds  toolkit.legacyUserProfileCustomizations.stylesheets = true  to user.js

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/matteoninotti/firefox-nova-islands/main"
CSS_NAME="nova-islands.css"
IMPORT_LINE='@import url("nova-islands.css");'
IMPORT_RE='^@import url\("nova-islands\.css"\);'$'\r''?$'
PREF_LINE='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true); // firefox-nova-islands'
PREF_MARK='// firefox-nova-islands'

usage() {
  cat <<'USAGE'
Usage:
  install.sh                     pick a profile interactively and install
  install.sh --profile <dir>     install into a specific profile folder
  install.sh --uninstall [...]   remove it again
USAGE
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

# Read answers from the terminal even when the script is piped (curl | bash).
ask() {
  local prompt=$1 reply=""
  if ! { read -r -p "$prompt" reply </dev/tty; } 2>/dev/null; then
    printf '\n' >&2
    die "no answer read from the terminal; pass --profile <dir>"
  fi
  printf '%s' "$reply"
}

PROFILE=""
UNINSTALL=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile) [[ $# -ge 2 ]] || die "--profile needs a folder"; PROFILE=$2; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

# ---- Find Firefox profile roots ------------------------------------------

candidate_roots() {
  if [[ -n ${FIREFOX_ROOT:-} ]]; then
    printf '%s\n' "$FIREFOX_ROOT"
    return
  fi
  case $(uname -s) in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/Firefox" ;;
    *)
      printf '%s\n' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox" \
        "$HOME/.mozilla/firefox" \
        "$HOME/snap/firefox/common/.mozilla/firefox" \
        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" \
        "$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox" ;;
  esac
}

# Prints "<absolute profile path>\t<is default 0|1>" for each profile.
list_profiles() {
  local root=$1 ini="$1/profiles.ini"
  [[ -f $ini ]] || return 0
  awk -v root="$root" '
    function flush() {
      if (section ~ /^Profile/ && path != "") {
        full = (relative == "0") ? path : root "/" path
        profiles[++n] = full
        isdef[full] = (isdef[full] || def == "1")
      }
      path = ""; relative = "1"; def = ""
    }
    { sub(/\r$/, "") }
    /^\[/ { flush(); section = substr($0, 2, length($0) - 2); next }
    {
      eq = index($0, "="); if (!eq) next
      key = substr($0, 1, eq - 1); val = substr($0, eq + 1)
      if (section ~ /^Profile/) {
        if (key == "Path") path = val
        else if (key == "IsRelative") relative = val
        else if (key == "Default") def = val
      } else if (section ~ /^Install/ && key == "Default") {
        installdef[(val ~ /^\//) ? val : root "/" val] = 1
      }
    }
    END {
      flush()
      # Firefox 67+ picks the profile named in [Install...]; the older
      # Default=1 flag only counts when there is no such section.
      has_install = 0
      for (i = 1; i <= n; i++) if (profiles[i] in installdef) has_install = 1
      for (i = 1; i <= n; i++) {
        p = profiles[i]
        print p "\t" (has_install ? ((p in installdef) ? 1 : 0) : (isdef[p] ? 1 : 0))
      }
    }
  ' "$ini"
}

choose_profile() {
  local root line path def i=0 choice default_index=""
  local -a paths=()
  while IFS= read -r root; do
    while IFS=$'\t' read -r path def; do
      [[ -d $path ]] || continue
      paths+=("$path")
      i=${#paths[@]}
      if [[ $def == 1 && -z $default_index ]]; then default_index=$i; fi
      printf '  [%d] %s%s\n' "$i" "$path" "$([[ $def == 1 ]] && printf '  (default)')" >&2
    done < <(list_profiles "$root")
  done < <(candidate_roots)

  [[ ${#paths[@]} -gt 0 ]] || die "no Firefox profiles found; pass --profile <dir>"
  [[ -n $default_index ]] || default_index=1

  choice=$(ask "Profile number [$default_index]: ") || exit 1
  choice=${choice:-$default_index}
  [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#paths[@]} )) || die "invalid choice: $choice"
  printf '%s' "${paths[choice-1]}"
}

if [[ -z $PROFILE ]]; then
  info "Firefox profiles found:"
  PROFILE=$(choose_profile) || exit 1
fi
[[ -d $PROFILE ]] || die "profile folder not found: $PROFILE"
[[ -f $PROFILE/prefs.js || -f $PROFILE/times.json ]] || die "does not look like a Firefox profile: $PROFILE"

CHROME="$PROFILE/chrome"
USERCHROME="$CHROME/userChrome.css"
USERJS="$PROFILE/user.js"

if pgrep -x firefox >/dev/null 2>&1 || pgrep -x firefox-bin >/dev/null 2>&1 || pgrep -f 'Firefox.app/Contents/MacOS/firefox' >/dev/null 2>&1; then
  info "Note: Firefox is running. Changes take effect after you restart it."
fi

backup() {
  local dir
  dir=$(mktemp -d "$PROFILE/nova-islands-backup-$(date +%Y%m%d-%H%M%S)-XXXX")
  [[ -f $USERCHROME ]] && cp -p "$USERCHROME" "$dir/"
  [[ -f $USERJS ]] && cp -p "$USERJS" "$dir/"
  info "Backup: $dir"
}

# Remove every line matching regex $1 (mode "regex") or containing string $1
# (mode "contains") from file $3.
remove_lines() {
  local needle=$1 mode=$2 file=$3 tmp
  [[ -f $file ]] || return 0
  tmp=$(mktemp "$file.XXXXXX")
  if [[ $mode == contains ]]; then
    grep -vF -- "$needle" "$file" >"$tmp" || true
  else
    grep -vE -- "$needle" "$file" >"$tmp" || true
  fi
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# ---- Uninstall ------------------------------------------------------------

if (( UNINSTALL )); then
  backup
  rm -f "$CHROME/$CSS_NAME"
  remove_lines "$IMPORT_RE" regex "$USERCHROME"
  remove_lines "$PREF_MARK" contains "$USERJS"
  info "Removed firefox-nova-islands from $PROFILE"
  info "The stylesheet pref stays enabled in prefs.js; reset it in about:config if nothing else needs it."
  info "Restart Firefox to finish."
  exit 0
fi

# ---- Install --------------------------------------------------------------

# Use the CSS next to the script when run from a checkout; download it when piped (curl | bash).
SCRIPT_DIR=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
backup
mkdir -p "$CHROME"

if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/$CSS_NAME ]]; then
  cp "$SCRIPT_DIR/$CSS_NAME" "$CHROME/$CSS_NAME"
else
  info "Downloading $CSS_NAME ..."
  curl -fsSL "$REPO_RAW/$CSS_NAME" -o "$CHROME/$CSS_NAME" || die "download failed"
fi

# @import must come before any other rule, so put it on the first line.
if [[ -f $USERCHROME ]] && grep -qE -- "$IMPORT_RE" "$USERCHROME"; then
  :
else
  tmp=$(mktemp "$CHROME/userChrome.XXXXXX")
  printf '%s\n' "$IMPORT_LINE" >"$tmp"
  [[ -f $USERCHROME ]] && cat "$USERCHROME" >>"$tmp"
  cat "$tmp" >"$USERCHROME"
  rm -f "$tmp"
fi

if ! { [[ -f $USERJS ]] && grep -qF -- "$PREF_MARK" "$USERJS"; }; then
  # Make sure the pref starts on its own line.
  if [[ -s $USERJS && $(tail -c1 "$USERJS" | od -An -c | tr -d ' ') != '\n' ]]; then
    printf '\n' >>"$USERJS"
  fi
  printf '%s\n' "$PREF_LINE" >>"$USERJS"
fi

info "Installed into $PROFILE"

if [[ -f $PROFILE/user-overrides.js ]]; then
  info ""
  info "Heads-up: this profile has a user-overrides.js (arkenfox/Betterfox updater)."
  info "Those updaters rewrite user.js, so also add this line to user-overrides.js:"
  info "  user_pref(\"toolkit.legacyUserProfileCustomizations.stylesheets\", true);"
fi

# Nova is on by default from Firefox 157; before that it needs browser.nova.enabled.
ff_major=""
if [[ -f $PROFILE/compatibility.ini ]]; then
  ff_major=$(sed -n 's/^LastVersion=\([0-9]*\).*/\1/p' "$PROFILE/compatibility.ini" | head -n1)
fi
nova_note=0
if grep -qF 'user_pref("browser.nova.enabled", false);' "$PROFILE/prefs.js" 2>/dev/null; then
  nova_note=1
elif [[ -n $ff_major ]] && (( ff_major < 157 )) &&
     ! grep -qF 'user_pref("browser.nova.enabled", true);' "$PROFILE/prefs.js" 2>/dev/null; then
  nova_note=1
fi
if (( nova_note )); then
  info ""
  info "Note: the Nova design is off in this profile, and this style only applies to Nova."
  info "Set browser.nova.enabled to true in about:config to see it."
fi

info ""
info "Restart Firefox to apply."
