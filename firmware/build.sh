#!/usr/bin/env bash
#
# keydeck: сборка и прошивка через arduino-cli с проектным конфигом.
#
#   ./firmware/build.sh                  собрать keydeck
#   ./firmware/build.sh --upload         собрать и прошить keydeck
#   ./firmware/build.sh --scan           собрать сканер пинов
#   ./firmware/build.sh --scan --upload  собрать и прошить сканер
#
# Переменные окружения:
#   PORT  порт платы (по умолчанию /dev/cu.usbmodem1101)
#
# Конфиг .arduino-cli.yaml держит ядро, библиотеки и кэш внутри проекта, чтобы
# не трогать ~/Library/Arduino15. Пропатченная ESP32 BLE Keyboard подключается
# через --library из firmware/libs/ — см. firmware/libs/ESP32_BLE_Keyboard/KEYDECK-PATCH.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_CONFIG="$ROOT/.arduino-cli.yaml"

# Без hwcdc/cdc Serial на S3 молчит — см. README.
FQBN="esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc"
PORT="${PORT:-/dev/cu.usbmodem1101}"

SKETCH="$ROOT/firmware/keydeck"
UPLOAD=0

for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    --scan)   SKETCH="$ROOT/firmware/keydeck_scan" ;;
    -h|--help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "неизвестный аргумент: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -f "$CLI_CONFIG" ]; then
  echo "нет $CLI_CONFIG — запусти из корня проекта" >&2
  exit 1
fi

BUILD="$ROOT/build/$(basename "$SKETCH")"

cmd=(arduino-cli --config-file "$CLI_CONFIG" compile
     --build-path "$BUILD"
     --library "$ROOT/firmware/libs/ESP32_BLE_Keyboard"
     -b "$FQBN")

if [ "$UPLOAD" = 1 ]; then
  cmd+=(--upload -p "$PORT")
fi

cmd+=("$SKETCH")

echo "+ ${cmd[*]}"
exec "${cmd[@]}"
