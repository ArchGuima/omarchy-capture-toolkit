# Capture Toolkit

A compact, retro-minimalist bar widget plugin for [Omarchy](https://omarchy.org/) that gathers Omarchy's native capture and recording utilities into one keyboard-friendly panel.

![Capture Toolkit preview](preview.png)

## Features

- **Screenshots:** Region (`1`), Fullscreen (`2`), Window (`3`), Scroll (`4`), plus an `[ ] Annotate` (`e`) toggle (`--editor=overlay`)
- **Screen Recording:** Retro toggles for Desktop Audio (`a`), Microphone (`m`), Fullscreen (`f`), and Webcam (`w`), live `REC` status indicator on the bar, one-click Stop (`r`), and live webcam overlay resize controls (`-`, `0`, `+`)
- **Utilities:** OCR Text Capture (`t`), QR Code Reader (`q`), Color Picker (`c`), and Media Transcoder (`v`)
- **Quick Folders:** Direct links to Screenshots and Videos directories
- **Bar Shortcuts:** Left-click toggles the panel; right-click takes a quick smart screenshot (or stops an active recording)
- **Theme & i18n Ready:** Uses Omarchy `qs.Ui` / `qs.Commons` theme tokens (works on dark and light themes), respects `omarchy toggle animations`, and supports `en`, `pt-BR`, and `pt`

## Installation

```bash
omarchy plugin add https://github.com/ArchGuima/omarchy-capture-toolkit --enable
omarchy bar put archguima.capture-toolkit --section right
```

## Keyboard Navigation

| Key | Action |
| :--- | :--- |
| `Arrows` / `hjkl` | Move cursor across tiles and toggles |
| `Enter` / `Space` | Activate focused item |
| `Esc` | Close panel |
| `Tab` / `Shift+Tab` | Switch to adjacent bar panels |
| `1` `2` `3` `4` | Region / Fullscreen / Window / Scroll screenshot |
| `e` | Toggle annotation overlay for screenshots |
| `a` `m` `f` `w` | Toggle Desktop Audio / Mic / Fullscreen / Webcam |
| `r` | Start or stop screen recording |
| `-` `0` `+` | Resize active webcam overlay while recording |
| `t` `q` `c` `v` | OCR / QR Code / Color HEX / Transcode |

## Optional Hyprland Keybinding

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + C", "Capture Toolkit", { panel = "archguima.capture-toolkit" })
```

## Security & Privacy

- Zero network requests and zero background telemetry
- Strict allowlists for all shell commands invoked from the panel (`Model.js`)
- Plain-text rendering (`Text.PlainText`) and markup neutralization on tooltip text
- Safe folder opening via `xdg-user-dir` without sourcing shell files

## Development & Tests

```bash
omarchy plugin validate .
node --test tests/model.test.mjs
```
