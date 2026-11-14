# Development

## Build it yourself

```sh
git clone https://github.com/javedh-dev/ScaleBar.git && cd ScaleBar
Scripts/make-cert.sh   # once: a local signing certificate, so macOS remembers the Accessibility permission
Scripts/build.sh       # builds build/ScaleBar.app and runs a quick self-test
open build/ScaleBar.app
```

You only need Xcode or the Command Line Tools.

## Pipelines

| Workflow | Runs | Does |
| --- | --- | --- |
| **CI** | every push and PR | builds the app and runs the self-test |
| **Release** | manually: Actions → Release | bumps `.version`, builds, tags, publishes the zip + checksum, updates the Homebrew cask |
| **Docs** | push to `main` touching `docs/` | builds this site and deploys it to GitHub Pages |

To ship: **Actions → Release → Run workflow**, pick `patch`, `minor` or `major` (`none` ships `.version` as is).

Optional: run `Scripts/make-cert.sh --ci` once and add the two secrets it prints, so every release is signed with the same certificate and users keep their Accessibility permission across updates.

## Docs

```sh
cd docs && npm install && npm run dev
```
