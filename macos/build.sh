#!/usr/bin/env bash
#
# keydeck для macOS: сборка .app через swiftc.
# Xcode не нужен — достаточно Command Line Tools.
#
#   ./macos/build.sh          собрать macos/build/Keydeck.app
#   ./macos/build.sh --run    собрать и запустить
#   ./macos/build.sh --clean  удалить сборку

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS="$ROOT/macos"
APP="$MACOS/build/Keydeck.app"
BIN="$APP/Contents/MacOS/Keydeck"
BUNDLE_ID="ru.evgeniy.keydeck"

run=0
for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    --clean) rm -rf "$MACOS/build"; echo "удалено: $MACOS/build"; exit 0 ;;
    -h|--help) sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "неизвестный аргумент: $arg" >&2; exit 2 ;;
  esac
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$MACOS/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "+ swiftc"
swiftc -swift-version 5 -O \
  -o "$BIN" \
  "$MACOS"/Sources/*.swift \
  -framework AppKit -framework CoreGraphics -framework ApplicationServices

# Подпись. Свой сертификат (make-signing-cert.sh) даёт ПОСТОЯННУЮ идентичность:
# разрешение Accessibility выдаётся один раз и переживает пересборку. У ad-hoc
# подписи идентичность привязана к хешу сборки, поэтому разрешение слетает
# каждый раз — используем её только как запасной вариант.
IDENTITY="$(security find-certificate -c keydeck-dev -Z 2>/dev/null | awk '/SHA-1 hash:/{print $3}')"
if [ -n "$IDENTITY" ] && codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1; then
  echo "+ подписано сертификатом keydeck-dev"
elif codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1; then
  echo "+ подписано ad-hoc — разрешение Accessibility придётся выдавать заново после каждой пересборки"
  echo "  постоянная подпись: ./macos/make-signing-cert.sh"
else
  echo "! подписать не удалось"
fi

echo "готово: $APP"

if [ "$run" = 1 ]; then
  echo "+ запуск"
  open "$APP"
fi
