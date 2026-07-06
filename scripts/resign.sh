#!/bin/bash
# Makes an installed copy of Mail Filename Fix runnable on this Mac without
# a paid Apple Developer ID: strips the quarantine attribute and re-signs the
# bundle with a local ad-hoc signature.
#
# This script is bundled into the app itself (Contents/Resources/resign.sh),
# so every installer — install.sh, the Homebrew cask, or a human in Terminal —
# performs exactly the same, version-matched steps by invoking it.
#
# Usage:
#   resign.sh [path-to-app]   # defaults to the bundle containing this script
set -euo pipefail

if [[ $# -ge 1 ]]; then
    APP="$1"
else
    # .../Mail Filename Fix.app/Contents/Resources/resign.sh -> the .app itself
    APP="$(cd "$(dirname "$0")/../.." && pwd)"
fi
[[ -d "$APP" && "$APP" == *.app ]] || {
    echo "resign.sh: '$APP' is not an .app bundle" >&2
    exit 1
}
APPEX="$APP/Contents/PlugIns/FilenameFixExtension.appex"
[[ -d "$APPEX" ]] || { echo "resign.sh: extension not found in '$APP'" >&2; exit 1; }

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Mail requires its extensions to be sandboxed, so the ad-hoc signature must
# keep the app-sandbox entitlement (and nothing else — a development-signed
# build carries get-task-allow, which must not survive re-signing).
ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
PLIST

# Sign the nested extension first, then the containing app.
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APPEX"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
