# Dotfiles

Managed by [mise](https://mise.jdx.dev/) bootstrap with [fnox](https://fnox.jdx.dev/) secrets.

## New machine setup

### Prerequisites

1. **Install mise**: <https://mise.jdx.dev/getting-started.html>
2. **Install Proton Pass CLI**: <https://proton.me/pass/download>
   (Bitwarden CLI, fnox, and age are installed automatically by mise)

### Bootstrap

```sh
# 1. Adopt the shared dotfile history (restores tracked config files)
mise bootstrap --adopt git@github.com:mikkelkaysen/dotfiles.git --yes

# 2. Install tools (fnox, age, bitwarden CLI, etc.)
mise install

# 3. Authenticate to secret providers
bw login
pass-cli login

# 4. Bootstrap with secrets injected via fnox
export BW_SESSION=$(bw unlock --raw)
fnox exec -- mise bootstrap --yes

# 5. Verify
mise dot status
```

### How it works

- **Tracked files** are stored under `home/` and `config/` paths in this repository
- **Secrets** are managed by fnox using Bitwarden and Proton Pass providers
- **Secret values never enter this repository** — only vault item references in `~/.config/fnox/config.toml` (tracked here, but contains only references, not values)
- **Templates** (like `~/.zshenv`) are rendered from `{{ secret() }}` placeholders during `fnox exec -- mise bootstrap`

### Sync modes

- **manual** (default): local history saves automatically; run `mise dot sync` to push/pull
- **sync**: automatic two-way sharing (enable with `mise settings set history.sync sync`)
