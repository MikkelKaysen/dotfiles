# btop Catppuccin theme sync

`theme-sync.sh` selects the Catppuccin theme for btop: Mocha (dark) or Latte (light).
It creates or updates `themes/catppuccin.theme` as a symlink to
`catppuccin_mocha.theme` or `catppuccin_latte.theme`, and `btop.conf` uses
`color_theme = "catppuccin"`.

## Usage

```sh
zsh -f ~/.config/btop/theme-sync.sh           # auto detection
zsh -f ~/.config/btop/theme-sync.sh dark      # Mocha (also: true, 1)
zsh -f ~/.config/btop/theme-sync.sh light     # Latte (also: false, 0)
```

Arguments are case-insensitive. A missing or unrecognized argument uses auto detection.
Successful runs print nothing; errors go to stderr.

The `btop` shell function in `~/.zshrc` runs the script with `zsh -f` before each
launch. The script's stdout is not redirected, so btop still sees a terminal.
Errors are hidden, and btop always starts with its original arguments.

## Auto detection order

1. **Terminal background (OSC 11).** Used only when stdin and stdout are a tty and
   `TERM` is not `dumb`, `linux`, `screen*`, or `tmux*`, and not inside tmux/screen.
   The query is skipped if keyboard input is already pending. It waits at most about
   0.3 s and accepts only a strict `rgb:` reply. There is no cache.
2. **OS appearance.**
   - macOS: `defaults read -g AppleInterfaceStyle`. Missing means light.
   - WSL: `reg.exe query HKCU\...\Themes\Personalize /v AppsUseLightTheme`.
     `0x0` means dark and `0x1` means light.
   - Linux: `gsettings org.gnome.desktop.interface color-scheme`
     (`prefer-dark` or `prefer-light`). Legacy `~/.config/noctalia/settings.json`
     `.colorSchemes.darkMode` is read only if `jq` is installed.
3. **Unknown:** dark.

`jq` is optional and only used for the legacy Linux JSON fallback.

## Timing

btop reads its theme at startup. The wrapper selects the theme at the next btop
launch. It does not reload a theme in a running btop.

## Noctalia (not active on this WSL machine)

This WSL machine has no Noctalia configuration (`~/.config/noctalia` does not exist).
Nothing is installed or written for Noctalia here.

`noctalia-hook.toml` is a ready-to-enable hook snippet for a machine that runs
Noctalia. Current Noctalia uses TOML. Its `[hooks] theme_mode_changed` command runs
the script with `NOCTALIA_THEME_MODE` set to `dark` or `light`.

Install only on a Noctalia machine, after confirming an existing Noctalia config:

```sh
ln -s "${XDG_CONFIG_HOME:-$HOME/.config}/btop/noctalia-hook.toml" \
  "${NOCTALIA_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/noctalia}/btop-catppuccin.toml"
```

- Do not use `ln -f`; it could clobber an existing file.
- If the Noctalia config already has a `theme_mode_changed` hook, merge the command
  into that list. Do not add a second `[hooks]` table.
- Disable btop in Noctalia app theming: remove only `btop` from
  `[theme.templates] builtin_ids`. Keep the other templates. Disabling it may delete
  the generated `btop/themes/noctalia.theme`. Back that file up first if you want it.
- The hook's exact syntax is verified against current upstream docs. Legacy hook
  syntax is not supported.

## Manual override

```sh
zsh -f ~/.config/btop/theme-sync.sh dark
zsh -f ~/.config/btop/theme-sync.sh light
```

## Files

- `theme-sync.sh`: selects Mocha or Latte and updates the `catppuccin.theme` symlink.
- `noctalia-hook.toml`: optional Noctalia hook snippet, not active.
- `themes/catppuccin_mocha.theme`, `themes/catppuccin_latte.theme`: theme files
  (the official theme and license are added by a separate change).
- `themes/noctalia.theme`: unchanged.
