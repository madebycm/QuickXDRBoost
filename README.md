# QuickXDRBoost

QuickXDRBoost is a tiny macOS menu-bar app for boosting XDR display brightness and reducing white point.

It appears as a sun icon in the menu bar. Click the icon to adjust XDR boost, enable Reduce White Point up to 200%, turn on Launch at Login, open the GitHub repo from About, or quit the app.

Made by [madebycm](https://github.com/madebycm).

Repository: [github.com/madebycm/QuickXDRBoost](https://github.com/madebycm/QuickXDRBoost)

## What It Does

QuickXDRBoost keeps a hidden 1x1 EDR Metal overlay alive on supported displays and scales the display gamma table while macOS exposes HDR headroom.

Reduce White Point uses the same gamma-table curve as the standalone ReduceWhitePoint app:

```text
pow(input, 1 + intensity / 100 * 0.8)
```

The two effects are applied together in one display-table update, so XDR boost and Reduce White Point can be used at the same time without one overwriting the other.

## Requirements

- macOS 13 or newer
- Apple Command Line Tools with `swiftc`
- A supported built-in XDR MacBook display, Pro Display XDR, or Studio Display

You do not need full Xcode.

## Install

Clone the repo:

```sh
git clone https://github.com/madebycm/QuickXDRBoost.git
cd QuickXDRBoost
```

Build, install to `/Applications`, and launch:

```sh
make run
```

## Use

1. Look for the sun icon in the macOS menu bar.
2. Click it.
3. Move the `XDR boost` slider to control the extra brightness.
4. Enable `Reduce white point` and move its slider from `0%` to `200%` if you want a dimmer white point.
5. Enable `Launch at login` if you want the app to start automatically.
6. Choose `Quit QuickXDRBoost` when you want to stop all display changes.

## Quit From Terminal

```sh
/Applications/QuickXDRBoost.app/Contents/MacOS/QuickXDRBoost off
```

Check whether it is running:

```sh
/Applications/QuickXDRBoost.app/Contents/MacOS/QuickXDRBoost status
```

## Build Only

```sh
make
```

The built app will be at:

```text
build/QuickXDRBoost.app
```

## Uninstall

Quit the app first, then remove it:

```sh
/Applications/QuickXDRBoost.app/Contents/MacOS/QuickXDRBoost off
rm -rf /Applications/QuickXDRBoost.app
```

## Troubleshooting

If the menu-bar icon does not appear, run:

```sh
open /Applications/QuickXDRBoost.app
```

If the display does not get brighter, make sure you are using a supported XDR display and that the system has HDR/EDR headroom available. Reduce White Point can still work without XDR boost.

If colors look wrong after quitting, open System Settings and toggle your display color profile, or log out and back in. Most users should not need that; quitting QuickXDRBoost should restore the display state.

## License

MIT. See [LICENSE](LICENSE).
