#!/bin/sh
# Self-signed code-signing certificate "ScaleBar Local", so the Accessibility permission belongs to builds signed
# with it (and survives rebuilds/updates), not to anything named "local.scalebar".
#
#   Scripts/make-cert.sh        once per Mac: adds it to your login keychain for local builds.
#                         Undo: Keychain Access → login → delete "ScaleBar Local" (certificate + key).
#   Scripts/make-cert.sh --ci   makes a separate certificate for GitHub Actions release builds and prints the two
#                         secrets to add (Settings → Secrets and variables → Actions). Nothing is kept on disk.
set -e
D=$(mktemp -d) && trap 'rm -rf "$D"' EXIT && umask 077
if [ "$1" != "--ci" ] && security find-identity -p codesigning | grep -q "ScaleBar Local"; then echo "Already exists."; exit 0; fi
/usr/bin/openssl req -x509 -newkey rsa:2048 -keyout "$D/k.pem" -out "$D/c.pem" -days 3650 -nodes -subj "/CN=ScaleBar Local" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" -addext "basicConstraints=critical,CA:false" 2>/dev/null
P=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$D/k.pem" -in "$D/c.pem" -out "$D/c.p12" -passout "pass:$P"

if [ "$1" = "--ci" ]; then
    if command -v gh >/dev/null; then
        base64 -i "$D/c.p12" | gh secret set SIGNING_P12 && printf %s "$P" | gh secret set SIGNING_P12_PASSWORD
        echo "Secrets set on $(gh repo view --json nameWithOwner -q .nameWithOwner)."
    else
        echo "Add these two repository secrets on GitHub (Settings → Secrets and variables → Actions → New):"
        echo; echo "SIGNING_P12_PASSWORD:"; echo "$P"
        echo; echo "SIGNING_P12:"; base64 -i "$D/c.p12"
        echo; echo "Then clear this terminal. Keep them secret: they can sign apps as ScaleBar."
    fi
else
    security import "$D/c.p12" -k ~/Library/Keychains/login.keychain-db -P "$P" -T /usr/bin/codesign
    echo "Created. Now run Scripts/build.sh"
fi
