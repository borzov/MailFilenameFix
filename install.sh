#!/bin/bash
# Installer for Mail Filename Fix.
#
# Downloads the latest release from GitHub, installs it into /Applications,
# strips the quarantine attribute and re-signs the app with a local ad-hoc
# signature, so Gatekeeper treats it like a locally built app. This is what
# makes distribution possible without a paid Apple Developer ID.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/borzov/MailFilenameFix/master/install.sh | bash
set -euo pipefail

REPO="borzov/MailFilenameFix"
APP_NAME="Mail Filename Fix.app"
DEST="/Applications"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || die "этот скрипт предназначен только для macOS."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

info "Ищу последнюю версию…"
DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"browser_download_url": *"\([^"]*\.zip\)".*/\1/p' | head -1)
[[ -n "$DOWNLOAD_URL" ]] || die "не удалось найти свежий выпуск на GitHub. Проверьте соединение."

info "Скачиваю: $DOWNLOAD_URL"
curl -fSL --progress-bar -o "$TMP/app.zip" "$DOWNLOAD_URL"
ditto -xk "$TMP/app.zip" "$TMP/unpacked"
[[ -d "$TMP/unpacked/$APP_NAME" ]] || die "в архиве не оказалось «$APP_NAME»."

# Quit a running instance before replacing it (the app is a background agent,
# so it is usually not running at all).
osascript -e "quit app \"${APP_NAME%.app}\"" >/dev/null 2>&1 || true

info "Устанавливаю в $DEST…"
SUDO=""
if ! { rm -rf "$DEST/$APP_NAME" && ditto "$TMP/unpacked/$APP_NAME" "$DEST/$APP_NAME"; } 2>/dev/null; then
    info "Нужны права администратора (пароль вашего пользователя macOS)."
    SUDO="sudo"
    $SUDO rm -rf "$DEST/$APP_NAME"
    $SUDO ditto "$TMP/unpacked/$APP_NAME" "$DEST/$APP_NAME"
fi

info "Снимаю карантин и переподписываю локально…"
# The re-sign logic ships inside the bundle, so it always matches the
# installed version.
$SUDO bash "$DEST/$APP_NAME/Contents/Resources/resign.sh" "$DEST/$APP_NAME" \
    || die "переподпись не удалась."

info "Запускаю приложение, чтобы Почта увидела расширение…"
open "$DEST/$APP_NAME"

cat <<'EOF'

Готово! Осталось два шага:

  1. Откройте Почту: Почта → Настройки → Расширения
     и поставьте галочку напротив «Filename Fix».
  2. Перезапустите Почту.

После этого имена вложений вида «utf-8''%D0%93…» будут отображаться правильно.
EOF
