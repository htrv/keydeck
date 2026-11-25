#!/usr/bin/env bash
#
# Создаёт самоподписанный сертификат для локальной подписи приложения.
#
# Зачем: у ad-hoc подписи (`codesign --sign -`) идентичность привязана к хешу
# сборки, поэтому после каждой пересборки macOS считает приложение новым и
# требует выдать разрешение Accessibility заново. С постоянным сертификатом
# разрешение выдаётся один раз.
#
# Запускать один раз:  ./macos/make-signing-cert.sh
# Сертификат недоверенный (CSSMERR_TP_NOT_TRUSTED) — для локальной подписи этого
# достаточно, `codesign` с ним работает. Ключи остаются в
# ~/Library/Application Support/keydeck/signing, чтобы идентичность можно было
# восстановить, не создавая новую (иначе разрешение слетит).

set -euo pipefail

DEST="$HOME/Library/Application Support/keydeck/signing"
CN="keydeck-dev"
PASS="keydeck"

if security find-certificate -c "$CN" >/dev/null 2>&1; then
  echo "сертификат '$CN' уже есть в связке ключей — ничего не делаю"
  exit 0
fi

mkdir -p "$DEST"

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$DEST/key.pem" -out "$DEST/cert.pem" \
  -subj "/CN=$CN/O=keydeck" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

# Старые алгоритмы шифрования контейнера: иначе security import не читает p12.
openssl pkcs12 -export -out "$DEST/id.p12" \
  -inkey "$DEST/key.pem" -in "$DEST/cert.pem" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:$PASS" >/dev/null 2>&1

security import "$DEST/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "готово: сертификат '$CN' импортирован в связку ключей"
echo "файлы: $DEST"
