#!/bin/bash
# One-time: creates a self-signed code-signing identity "Kursor Local Signing" in the
# login keychain. A stable signature lets macOS remember Kursor's permissions across
# rebuilds. Remove later with Keychain Access (search "Kursor Local Signing").
set -euo pipefail

NAME="Kursor Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "identity \"$NAME\" already exists"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cfg" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = ext
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# System LibreSSL writes PKCS#12 that `security import` understands (OpenSSL 3 needs -legacy).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cfg" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout pass:kursor

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P kursor -T /usr/bin/codesign
echo "created \"$NAME\""
