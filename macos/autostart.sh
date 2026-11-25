#!/usr/bin/env bash
#
# Автозапуск keydeck при логине (LaunchAgent).
#
#   ./macos/autostart.sh --install     включить автозапуск
#   ./macos/autostart.sh --uninstall   выключить
#   ./macos/autostart.sh --status      показать состояние
#
# Требуется собранное приложение: сначала ./macos/build.sh.
# Разрешение Accessibility выдаётся один раз и привязано к подписи приложения,
# поэтому автозапуск его не сбрасывает.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/macos/build/Keydeck.app"
EXEC="$APP/Contents/MacOS/Keydeck"
LABEL="com.keydeck.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

usage() {
  sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

install_agent() {
  if [ ! -x "$EXEC" ]; then
    echo "нет сборки: $EXEC" >&2
    echo "сначала собери: ./macos/build.sh" >&2
    exit 1
  fi

  mkdir -p "$HOME/Library/LaunchAgents"

  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXEC</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <!-- KeepAlive выключен намеренно: иначе «Выйти» из меню тут же перезапускает
         приложение и выйти становится невозможно. -->
    <key>KeepAlive</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/keydeck.agent.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/keydeck.agent.log</string>
</dict>
</plist>
PLIST_EOF

  # Перезагружаем, чтобы применились свежие пути (пересборка могла их не менять,
  # но bootstrap на уже загруженный агент вернёт ошибку).
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  echo "автозапуск включён: $PLIST"
  echo "приложение запущено сейчас, и будет подниматься при каждом логине"
}

uninstall_agent() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "автозапуск выключен (агент выгружен, $PLIST удалён)"
  echo "само приложение, если запущено, продолжает работать — выйти можно из меню ⌨"
}

status_agent() {
  if [ -f "$PLIST" ]; then
    echo "plist: $PLIST"
  else
    echo "plist: нет (автозапуск не включён)"
  fi
  if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    echo "агент: загружен"
    launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E "state =|pid =|program =|last exit" | head -5
  else
    echo "агент: не загружен"
  fi
  if pgrep -f "Keydeck.app/Contents/MacOS/Keydeck" >/dev/null; then
    echo "процесс приложения: запущен (pid $(pgrep -f 'Keydeck.app/Contents/MacOS/Keydeck' | tr '\n' ' '))"
  else
    echo "процесс приложения: не запущен"
  fi
}

case "${1:-}" in
  --install) install_agent ;;
  --uninstall) uninstall_agent ;;
  --status) status_agent ;;
  *) usage ;;
esac
