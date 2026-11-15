# FAQ

## Why does my external monitor look blurry on my Mac?
Usually you've picked a "scaled" size like 2048×1152 on a 1440p monitor. macOS draws it at that size and stretches it to fit the panel. Pick the same size in ScaleBar (1.25x) and it's rendered as HiDPI instead, so it stays crisp.

## How do I turn on HiDPI for a 1440p or 1080p monitor on Apple Silicon?
macOS ignores the old display-override trick on Apple Silicon. ScaleBar creates a virtual HiDPI display at the size you choose and mirrors your monitor from it. Just pick a scale.

## Is 1.5x as sharp as 1x or 2x?
1x and 2x map pixels exactly. In-between sizes are drawn at double resolution and scaled down, which looks much better than macOS's normal scaling, but isn't quite pixel-perfect.

## Why can't I get 100Hz or 144Hz?
ScaleBar uses the highest refresh rate your monitor offers at full resolution. If macOS doesn't list it, the cable is usually the reason: USB-C cables that also carry USB data often only have bandwidth for 60–75Hz at 1440p. Try a USB-C to DisplayPort cable, or the monitor's "USB-C priority: high resolution" option.

## What happens if ScaleBar crashes?
macOS removes the virtual display and your monitor goes back to normal. If something looks stuck, run `killall ScaleBar`.

## Does it read my keyboard?
It only reacts to the brightness and volume keys. Every other key goes straight through and is never stored or logged.

## Does ScaleBar send any data?
Yes, a little. A daily update check to GitHub (optional), a daily anonymous count with only the app version (always), and, if you allow it, diagnostics: macOS version, processor type, screen count, your country (looked up from your IP address, which is not stored), which features are on, and, when something fails, a short error name and the model name of your external monitor. Settings shows exactly what is sent. See the [privacy policy](/privacy).

## How is this different from BetterDisplay or MonitorControl?
They're great and do much more. ScaleBar does fewer things, in a small, free, open-source app.
