# QuickXDRBoost

QuickXDRBoost is a tiny macOS menu-bar app that applies a BrightIntosh-style XDR brightness boost. It keeps a hidden 1x1 EDR Metal overlay alive on supported displays and scales the display gamma table while HDR headroom is available.

## Build

Full Xcode is not required. Apple's Command Line Tools with `swiftc` are enough.

```sh
make
```

## Install and Run

```sh
make run
```

The app appears as a sun icon in the menu bar. Open it to adjust the boost slider or quit.

You can also quit it from the command line:

```sh
/Applications/QuickXDRBoost.app/Contents/MacOS/QuickXDRBoost off
```

## Notes

This is intentionally minimal. It targets supported built-in XDR MacBook displays and external Apple XDR displays. Quitting the app restores the original gamma tables and asks macOS to restore ColorSync display settings.
