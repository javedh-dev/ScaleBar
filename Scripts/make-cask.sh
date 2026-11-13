#!/bin/sh
# Prints the Homebrew cask for a release. The Release workflow writes it to <owner>/homebrew-tap/Casks/scalebar.rb.
#   Scripts/make-cask.sh <version> <zip sha256> <owner/repo> > Casks/scalebar.rb
set -e
V=$1 SHA=$2 REPO=$3
[ -n "$V" ] && [ -n "$SHA" ] && [ -n "$REPO" ] || { echo "usage: $0 <version> <sha256> <owner/repo>" >&2; exit 1; }
cat <<EOF
cask "scalebar" do
  version "$V"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/ScaleBar-#{version}.zip"
  name "ScaleBar"
  desc "Sharp HiDPI scaling, brightness and volume for external monitors"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "ScaleBar.app"

  # ScaleBar isn't notarized (that needs a paid Apple developer account), so without this macOS
  # would block the first launch. Only this app's quarantine flag is removed.
  postflight_steps do
    run "/usr/bin/xattr", args:           ["-dr", "com.apple.quarantine", "{{appdir}}/ScaleBar.app"],
                          writable_paths: ["{{appdir}}/ScaleBar.app"]
  end

  uninstall quit: "local.scalebar"

  zap trash: "~/Library/Preferences/local.scalebar.plist"
end
EOF
