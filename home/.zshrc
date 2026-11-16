################################################################################
# Zim Setup
################################################################################

# Download zimfw plugin manager if missing.
if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
  curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
      https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
fi

# Install missing modules, and update ${ZIM_HOME}/init.zsh if missing or outdated.
if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]]; then
  source ${ZIM_HOME}/zimfw.zsh init -q
fi

source ${ZIM_HOME}/init.zsh

################################################################################
#
################################################################################
# >>> mise:activate >>> managed by mise — do not edit between markers
eval "$(mise activate zsh)"
# <<< mise:activate <<<
# btop: sync the Catppuccin theme to the terminal/OS appearance before each launch.
# theme-sync.sh runs under zsh -f; its stdout is not redirected so btop keeps the tty.
# Errors are hidden and never block btop; btop's args and exit status are preserved.
btop() { zsh -f "${XDG_CONFIG_HOME:-$HOME/.config}/btop/theme-sync.sh" 2>/dev/null || true; command btop "$@"; }
