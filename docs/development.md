# Development

## Build it yourself

```sh
git clone https://github.com/javedh-dev/ScaleBar.git && cd ScaleBar
Scripts/make-cert.sh   # once: a local signing certificate, so macOS remembers the Accessibility permission
Scripts/build.sh       # builds build/ScaleBar.app and runs a quick self-test
open build/ScaleBar.app
```

You only need Xcode or the Command Line Tools.

## Usage count and diagnostics

Local builds send nothing. To enable it, set `TALLYMOTH_URL` (base URL, no `/v1/events`), `TALLYMOTH_KEY` (signed key id) and `TALLYMOTH_SECRET` before running `Scripts/build.sh`. Releases read them from the Actions secrets of the same names.

### tallymoth server setup

1. Make a signed key: `tallymoth keygen signed`. The app needs both the id and the secret.
2. Put the secret in the server's environment as `SCALEBAR_KEY`, and add this tenant to `tallymoth.yaml`:

```yaml
version: 1
tenants:
  - id: scalebar
    auth: {mode: signed, pow_bits: 16}
    keys: [{id: k_XXXXXXXX, secret: "${SCALEBAR_KEY}"}]   # id from keygen
    read_keys: [{id: r1, sha256: "..."}]                  # tallymoth keygen read, for Grafana
    retention_days: 365
    limits: {daily_cap: 20000, max_batch_events: 5, ip_per_minute: 10}
    events:
      ping:    [version]
      active:  [version, os, arch, displays, virtual, ddc, keys, country]
      failure: [version, kind, code, monitor, country]
```

3. Check it with `tallymoth config validate tallymoth.yaml`, then reload with `SIGHUP`. Behind a proxy, set `trust_proxy: true` so the per-IP limit sees real addresses.
4. Add the id, secret and server URL as the three Actions secrets.

The secret is stored inside the app, so anyone can read it. The strict schema, the rate limits and the daily cap are what limit abuse. Watch `daily_cap`: when it is hit, data stops.

### What the app sends

| Event | When | Props |
|---|---|---|
| `ping` | once a day, always | `version` |
| `active` | once a day, only with diagnostics on | `version`, `os`, `arch`, `displays`, `virtual`, `ddc`, `keys`, plus `country` added by the server |
| `failure` | on a failure, at most once a day per `kind`, only with diagnostics on | `version`, `kind`, `code`, `monitor`, plus `country` added by the server |

`kind` is one of `virtual_refused`, `mirror_failed`, `virtual_removed`, `display_config_failed`, `ddc_no_response`, `key_tap_failed`, `crash_virtual_display`. `code` is the macOS error number, or 0. `monitor` is the model name of the connected external monitor(s), such as `DELL U2723QE`, never a serial number.

### Country

The app never sends or looks up an IP address. The server turns the connection's IP into a country and stores only that, never the IP. Do it at your proxy or CDN (for example Cloudflare's `CF-IPCountry` header) or with a local GeoIP database. **tallymoth does not do this yet:** it needs a small change to copy a trusted country header into a `country` prop, only for the `active` and `failure` events and never for `ping`. Until that exists, leave this out and remove the country sentence from the privacy policy.

Useful queries: failures per kind (`event=failure&group_by=kind`), active count per version (`event=ping&group_by=version`), diagnostics users per country (`event=active&group_by=country`), and the share of users who share diagnostics (`active` count divided by `ping` count).

### Grafana dashboard

[Download `grafana-dashboard.json`](/ScaleBar/grafana-dashboard.json) and import it in Grafana (Dashboards, New, Import). It needs the Infinity datasource pointed at tallymoth's private port with the read key, as in the [tallymoth Grafana guide](https://javedh-dev.github.io/tallymoth/grafana). Pick that datasource in the dropdown at the top. It shows installs per day and by version, macOS version, Mac type, screens, feature use, country, and failures per day, by kind, by monitor and by app version.

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
