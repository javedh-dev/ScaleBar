# Privacy policy

*Last updated: 14 November 2026*

ScaleBar collects no personal data. There is no account, no crash reporting and no advertising. It counts how many Macs use it each day, anonymously, and can send diagnostics if you allow it (see below).

## What stays on your Mac

- **Your settings**, such as each monitor's scale, are stored locally in the app's preferences. They never leave your computer.
- **Keyboard keys.** To bring back brightness and volume keys, ScaleBar asks for the Accessibility permission. It reacts only to those keys. No other key is read, stored or logged.
- **Display information.** ScaleBar reads your monitors' modes and talks to them over DDC/CI to set brightness and volume. This stays on your Mac.

## Network requests

ScaleBar makes two kinds of request. The update check can be turned off in Settings. Diagnostics can be turned off too, but the daily version-only active count stays.

### Update check

Once a day ScaleBar asks GitHub whether a newer version exists. This is a plain request to the public GitHub releases API, so GitHub sees your IP address as it would for any web request, under [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). ScaleBar sends no identifier of its own.

It never downloads or installs anything by itself. Turn it off with **Check for updates automatically**.

### Anonymous active count and diagnostics

ScaleBar sends events to a [tallymoth](https://javedh-dev.github.io/tallymoth/) server run by the developer. ScaleBar explains this on first launch, and you can change your choice at any time in Settings.

#### Always: the active count

Once a day ScaleBar sends a `ping` event containing only the ScaleBar version. This tells the developer roughly how many people use each version. It cannot be turned off, and it contains nothing that identifies you or your Mac.

#### Optional: diagnostics

"Help improve ScaleBar by sharing diagnostics" is on by default, and you choose at first launch. When it is on, a daily `active` event with more detail is also sent, and failures are reported.

| Data | Example | Why |
|---|---|---|
| macOS version | `15.1` | Decide which macOS versions to support, and spot problems caused by a macOS update. |
| Processor type | `arm64` | Know whether Apple silicon and Intel both need testing. |
| Number of screens | `2` | Understand common setups. |
| Which features are on | virtual display, brightness and volume, keys | See which features are used, and which could be removed or improved. |
| Failure name | `ddc_no_response` | Know what went wrong. The names are a fixed list in the app, not free text. |
| macOS error number | `1001` | Narrow down the cause of a failure. `0` if there is none. |
| Country | `DE` | Know where ScaleBar is used, to prioritise languages and regions and to spot region-specific problems such as a network or a monitor model sold only in some countries. Worked out from your IP address by the server, which keeps only the country, never the IP. |
| External monitor model name | `DELL U2723QE` | Failures usually depend on the exact monitor, cable and macOS version. The model name lets the developer reproduce the problem, fix it, and keep the [compatibility list](/compatibility) accurate. Only sent with a failure. |

A failure is reported at most once a day per kind of failure.

#### What is never sent

Your IP address (only the country derived from it), a user ID, device ID, account, your name or email, city, coordinates, a monitor serial number or any other unique hardware identifier, setting values such as your scale choices, key presses, files, window contents, free-text error messages, or a list of your apps. ScaleBar does not create a random identifier either, so separate events cannot be tied to the same person or Mac.

#### How the data is handled

- **Your IP address.** Every request reveals your IP address to the server, as with any internet request. The server uses it for a moment to apply a rate limit and, with diagnostics on, to work out your country. The IP address itself is not stored, and neither is your user agent. ScaleBar itself never reads or sends your IP address. Country is never added to the version-only `ping`.
- **Where it is kept.** On a server run by the developer, in a database that holds only these counts. It is not sold, shared with advertisers, or used for profiling or tracking.
- **How long.** Events are deleted automatically after 365 days.
- **Who can see it.** Only the developer.
- **Why this is allowed to be collected.** It is used only to keep ScaleBar working and to improve it, which is the developer's legitimate interest. Because the data is anonymous and cannot be tied to you, it is not personal data in the usual sense. For the same reason, it cannot be looked up or deleted for one person. If you do not want to contribute diagnostics, turn them off. Only the version-only active count remains.
- **Children.** ScaleBar is a general utility, and the data contains nothing about the person using it.

#### Your controls

- **First launch:** the second welcome step lets you decline diagnostics.
- **Settings:** untick **Help improve ScaleBar by sharing diagnostics** at any time. It takes effect straight away.
- **Hover** over that option in Settings to see the list of what is sent.
- **Build from source** without the `TALLYMOTH_*` settings, and nothing is sent at all (see [Development](/development#usage-count-and-diagnostics)).

Builds without a server configured, such as ones you compile yourself, send nothing.

## Homebrew and downloads

If you install through Homebrew or from GitHub Releases, those services handle the download under their own policies. ScaleBar has no part in that.

## Changes and contact

If this policy changes, the new version is published here with a new date. Questions: [open an issue](https://github.com/javedh-dev/ScaleBar/issues).
