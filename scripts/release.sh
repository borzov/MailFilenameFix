#!/bin/bash
# Builds a distributable release: bumps the version, runs the tests, builds
# the app, packages it into dist/ and updates the Homebrew cask.
# Publishing (git push, gh release create) is left to the operator — the
# exact commands are printed at the end.
#
# Usage:
#   scripts/release.sh 1.2.3
#
# Environment:
#   TAP_DIR — path to the homebrew-tap checkout (default: ~/Develop/homebrew-tap)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAP_DIR="${TAP_DIR:-$HOME/Develop/homebrew-tap}"
CASK="$TAP_DIR/Casks/mail-filename-fix.rb"
APP_NAME="Mail Filename Fix.app"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Usage: scripts/release.sh <version>  (e.g. 1.2.3)" >&2
    exit 1
}
[[ -f "$CASK" ]] || { echo "Cask not found: $CASK (set TAP_DIR)" >&2; exit 1; }

cd "$REPO_ROOT"

echo "==> Bumping version to $VERSION"
sed -i '' "s/CFBundleShortVersionString: .*/CFBundleShortVersionString: $VERSION/" project.yml

echo "==> Running tests"
scripts/test.sh

echo "==> Building Release"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcodegen generate --quiet
xcodebuild -project MailFilenameFix.xcodeproj -scheme MailFilenameFix \
    -configuration Release -derivedDataPath "$BUILD_DIR" -quiet build
APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
[[ -x "$APP/Contents/Resources/resign.sh" || -f "$APP/Contents/Resources/resign.sh" ]] \
    || { echo "resign.sh missing from the built bundle" >&2; exit 1; }

echo "==> Packaging"
mkdir -p dist
ZIP="dist/MailFilenameFix-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

echo "==> Updating cask (version $VERSION, sha256 $SHA256)"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" "$CASK"

cat <<EOF

Release $VERSION is ready: $ZIP

To publish:
  git add project.yml && git commit -m "chore: release v$VERSION" && git push origin master
  gh release create v$VERSION "$ZIP" --title "v$VERSION" --notes-file dist/release-notes.md
  cd "$TAP_DIR" && git add Casks && git commit -m "mail-filename-fix $VERSION" && git push
EOF
