#!/bin/sh
set -e
cd "$(dirname "$0")/.."
A=build/ScaleBar.app
VERSION=$(cat .version)
# GitHub repo for update checks: from the git remote, or SCALEBAR_REPO=owner/name. Empty = update checks off.
REPO=${SCALEBAR_REPO:-$(git config --get remote.origin.url 2>/dev/null | sed -nE 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')}
rm -rf "$A" && mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
swiftc -O -import-objc-header Sources/ScaleBar/ScaleBar-Bridging-Header.h $(find Sources/ScaleBar -name "*.swift") -o "$A/Contents/MacOS/ScaleBar"

# App icon, drawn by the app itself (same glyph as the menu bar icon).
T=$(mktemp -d) && mkdir "$T/AppIcon.iconset"
"$A/Contents/MacOS/ScaleBar" --make-iconset "$T/AppIcon.iconset"
iconutil -c icns "$T/AppIcon.iconset" -o "$A/Contents/Resources/AppIcon.icns"
rm -rf "$T"

cp Resources/Info.plist "$A/Contents/Info.plist"
for kv in "CFBundleShortVersionString $VERSION" "CFBundleVersion $VERSION" "ScaleBarRepo $REPO"; do
    /usr/libexec/PlistBuddy -c "Set :${kv%% *} ${kv#* }" "$A/Contents/Info.plist"
done

# Signing. With the local certificate (make-cert.sh), the Accessibility grant is tied to that certificate and
# survives rebuilds. Without it, plain ad-hoc: secure, but macOS asks for Accessibility again after each rebuild.
if security find-identity -p codesigning | grep -q "ScaleBar Local"; then
    codesign -s "ScaleBar Local" --force "$A"
else
    echo "note: no 'ScaleBar Local' certificate (run scripts/make-cert.sh once); signing ad-hoc"
    codesign -s - --force "$A"
fi
"$A/Contents/MacOS/ScaleBar" --selftest
echo "Built $(pwd)/$A ($VERSION${REPO:+, updates from github.com/$REPO})"
