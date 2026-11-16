#!/usr/bin/env zsh
# Select the Catppuccin btop theme (Mocha = dark, Latte = light) for the next btop launch.
#
# Usage: theme-sync.sh [dark|light|true|false|1|0]   (case-insensitive; default: auto)
#   dark/true/1  -> catppuccin_mocha.theme
#   light/false/0 -> catppuccin_latte.theme
#   anything else (or no argument) -> auto detection:
#     1. terminal background via OSC 11 (only when stdin and stdout are a tty)
#     2. OS appearance: macOS defaults, WSL registry, Linux gsettings
#        (optional legacy Noctalia settings.json via jq)
#     3. unknown -> dark
#
# Writes themes/catppuccin.theme as a symlink to the chosen theme. Prints nothing
# on success; errors go to stderr. Intended to run as `zsh -f` from the btop wrapper.

emulate -LR zsh
setopt null_glob

zmodload zsh/datetime || return 1
zmodload zsh/zselect || return 1

typeset -g script_dir=${0:A:h}
typeset -g themes_dir=$script_dir/themes
typeset -g link_name=catppuccin.theme

# Capture the tty condition at entry, before any command substitution can
# turn stdout into a pipe.
typeset -g stdin_stdout_tty=0
[[ -t 0 && -t 1 ]] && stdin_stdout_tty=1

# ---- OSC 11 background query -------------------------------------------------

# Sets REPLY_MODE to dark|light on success; returns non-zero otherwise.
_btop_osc11_mode() {
  emulate -LR zsh
  local fd buf="" ch r g b w t deadline re_body
  local -a m
  REPLY_MODE=""

  # Only query a real terminal that understands OSC 11 (gate captured at entry).
  (( stdin_stdout_tty )) || return 1
  case ${TERM:-} in
    dumb|linux|screen*|tmux*) return 1 ;;
  esac
  [[ -n ${TMUX:-} || -n ${STY:-} ]] && return 1

  # Do not consume pending keyboard input.
  zselect -t 0 -r 0 && return 1

  exec {fd}<>/dev/tty 2>/dev/null || return 1
  {
    print -n -u $fd -- $'\e]11;?\a'
    deadline=$(( EPOCHREALTIME + 0.3 ))
    while true; do
      t=$(( deadline - EPOCHREALTIME ))
      (( t > 0 )) || break
      read -r -s -k1 -t $t -u $fd ch || break
      buf+=$ch
      (( ${#buf} <= 128 )) || break
      if [[ $buf == *$'\a' || $buf == *$'\e\\' ]]; then
        break
      fi
    done
  } always {
    exec {fd}>&-
  }

  # Strip the terminator, then require the exact reply shape.
  if [[ $buf == *$'\a' ]]; then
    buf=${buf%$'\a'}
  elif [[ $buf == *$'\e\\' ]]; then
    buf=${buf%$'\e\\'}
  else
    return 1
  fi
  re_body='^'$'\e''\]11;rgb:([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})$'
  [[ $buf =~ $re_body ]] || return 1
  r=${match[1]} g=${match[2]} b=${match[3]}

  # Weighted brightness (0..1) per component width.
  local -F lum rv gv bv scale
  w=${#r}; scale=$(( 16 ** w - 1 )); (( rv = (16#$r) * 1.0 / scale ))
  w=${#g}; scale=$(( 16 ** w - 1 )); (( gv = (16#$g) * 1.0 / scale ))
  w=${#b}; scale=$(( 16 ** w - 1 )); (( bv = (16#$b) * 1.0 / scale ))
  (( lum = 0.299 * rv + 0.587 * gv + 0.114 * bv ))
  if (( lum < 0.5 )); then REPLY_MODE=dark; else REPLY_MODE=light; fi
  return 0
}

# ---- OS appearance -----------------------------------------------------------

# Sets REPLY_MODE to dark|light on success; returns non-zero if unknown.
_btop_os_mode() {
  emulate -LR zsh
  local os out line settings v
  REPLY_MODE=""
  os=$(uname -s 2>/dev/null)

  if [[ $os == Darwin ]]; then
    # Key is absent in light mode.
    out=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
    if [[ $out == Dark ]]; then REPLY_MODE=dark; else REPLY_MODE=light; fi
    return 0
  fi

  if [[ $(uname -r 2>/dev/null) == [Mm]icrosoft* ]] && (( $+commands[reg.exe] )); then
    out=$(reg.exe query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v AppsUseLightTheme 2>/dev/null)
    for line in ${(f)out}; do
      line=${line%$'\r'}
      if [[ $line =~ '^[[:space:]]*AppsUseLightTheme[[:space:]]+REG_DWORD[[:space:]]+0x([01])$' ]]; then
        if [[ ${match[1]} == 0 ]]; then REPLY_MODE=dark; else REPLY_MODE=light; fi
        return 0
      fi
    done
    return 1
  fi

  # Legacy Noctalia settings.json (optional; requires jq).
  settings=${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/settings.json
  if (( $+commands[jq] )) && [[ -r $settings ]]; then
    v=$(jq -r '.colorSchemes.darkMode | if type == "boolean" then tostring else empty end' "$settings" 2>/dev/null)
    case $v in
      true) REPLY_MODE=dark; return 0 ;;
      false) REPLY_MODE=light; return 0 ;;
    esac
  fi

  if (( $+commands[gsettings] )); then
    v=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)
    v=${v//\'/}
    case $v in
      prefer-dark) REPLY_MODE=dark; return 0 ;;
      prefer-light) REPLY_MODE=light; return 0 ;;
    esac
  fi
  return 1
}

# ---- main --------------------------------------------------------------------

# Sets REPLY_FLAVOR to mocha|latte. No command substitution (keeps stdout a tty).
_btop_pick_flavor() {
  emulate -LR zsh
  local arg=${(L)1} mode
  REPLY_FLAVOR=mocha
  case $arg in
    dark|true|1) REPLY_FLAVOR=mocha; return 0 ;;
    light|false|0) REPLY_FLAVOR=latte; return 0 ;;
  esac

  if _btop_osc11_mode; then mode=$REPLY_MODE
  elif _btop_os_mode; then mode=$REPLY_MODE
  else mode=dark
  fi
  if [[ $mode == light ]]; then REPLY_FLAVOR=latte; else REPLY_FLAVOR=mocha; fi
  return 0
}

_btop_main() {
  emulate -LR zsh
  local flavor target link tmp
  _btop_pick_flavor "$1"
  flavor=$REPLY_FLAVOR
  target=catppuccin_${flavor}.theme

  if [[ ! -f $themes_dir/$target ]]; then
    print -u2 -r -- "btop theme-sync: missing theme $themes_dir/$target"
    return 1
  fi

  link=$themes_dir/$link_name
  # Refuse to replace user data: directories (including symlinks to them)
  # and regular files are never clobbered.
  if [[ -d $link ]]; then
    print -u2 -r -- "btop theme-sync: refusing to replace directory $link"
    return 1
  fi
  if [[ -e $link || -L $link ]]; then
    if [[ ! -L $link ]]; then
      print -u2 -r -- "btop theme-sync: refusing to replace non-symlink $link"
      return 1
    fi
    if [[ $(readlink -- "$link") == $target ]]; then
      return 0
    fi
  fi

  # Atomic replacement: create a unique sibling symlink (ln fails if it exists),
  # then rename it over the existing symlink.
  tmp=$themes_dir/.${link_name}.tmp.$$.$RANDOM
  ln -s -- "$target" "$tmp" || { print -u2 -r -- "btop theme-sync: cannot create $tmp"; return 1; }
  if ! mv -f -- "$tmp" "$link"; then
    rm -f -- "$tmp"
    print -u2 -r -- "btop theme-sync: failed to update $link"
    return 1
  fi
  return 0
}

_btop_main "$1"
