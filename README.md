# Dotfiles

Managed by [mise](https://mise.jdx.dev/) bootstrap with [fnox](https://fnox.jdx.dev/) secrets and [age](https://age-encryption.org/) encryption.

## How it works

- **Tracked files** are stored under `home/` and `config/` paths in this repository
- **Sensitive files** (`config.toml`, `zshenv.tmpl`, `fnox/config.toml`) are encrypted with age before they enter this repository — the history and origin hold only ciphertext
- **Secrets** are managed by fnox, cached locally as age-encrypted blobs in `~/.config/fnox/config.toml` (the `sync` field), so `mise` never re-prompts after the one-time entry
- **Two age keys** live on each machine, both untracked:
  - `~/.config/mise/age.txt` — decrypts mise history (with Bitwarden + YubiKey recovery recipients)
  - `~/.config/fnox/age.txt` — encrypts the fnox secret cache (machine-only, no recovery needed — re-sync from protonpass/bitwarden if lost)
- **Templates** (like `~/.zshenv`) are rendered from `{{ secret() }}` placeholders during `mse bootstrap` (= `fnox exec -- mise bootstrap`)
- **The `mse` alias** (defined by [zsh-mise](https://github.com/mikkelkaysen/zsh-mise)) runs mise through fnox so `[bootstrap.secrets]` resolve from the encrypted cache without prompting

## New machine setup

### Prerequisites

1. **Install mise**: <https://mise.jdx.dev/getting-started.html>
2. **Install Proton Pass CLI**: <https://proton.me/pass/download>
   (Bitwarden CLI, fnox, age, and age-plugin-yubikey are installed automatically by mise)

### Bootstrap

The tracked config files are encrypted, so a fresh machine needs a recovery key to decrypt the history before generating its own age key.

```sh
# 1. Adopt the shared dotfile history (encrypted — needs recovery key)
#    Retrieve the Bitwarden recovery identity from Bitwarden and write it to a temp file:
#      bw get item "mise-age-recovery" | jq -r '.notes' > /tmp/recovery.txt
export MISE_AGE_KEY_FILE=/tmp/recovery.txt
mise bootstrap --adopt git@github.com:mikkelkaysen/dotfiles.git --yes

# 2. Generate this machine's age keys (the pre-dotfiles hook does this, or manually)
mise exec -- age-keygen -o ~/.config/mise/age.txt && chmod 600 ~/.config/mise/age.txt
mise exec -- age-keygen -o ~/.config/fnox/age.txt && chmod 600 ~/.config/fnox/age.txt
unset MISE_AGE_KEY_FILE

# 3. Add this machine's public key (from age.txt) to both:
#    - ~/.config/mise/config.toml → [history.encryption].recipients
#    - ~/.config/fnox/config.toml → [providers.age].recipients

# 4. Re-encrypt history with the new recipients list (needs recovery key temporarily)
export MISE_AGE_KEY_FILE=/tmp/recovery.txt
mise dot save --re-encrypt
unset MISE_AGE_KEY_FILE
rm /tmp/recovery.txt

# 5. Authenticate to secret providers
bw login
pass-cli login

# 6. Cache secrets (one-time — no more --prompt-secrets needed)
export BW_SESSION=$(bw unlock --raw)
fnox sync -g ITM_LLM_GW_KEY      # protonpass → age cache
fnox set -g MINDS_GIT_EMAIL       # hidden prompt → age cache
fnox set -g WORK_GIT_EMAIL        # hidden prompt → age cache

# 7. Bootstrap with secrets injected via fnox
fnox exec -- mise bootstrap --yes

# 8. Verify
mse dot status
mse bootstrap secrets status    # all "available"
```

## Everyday workflow

```sh
mse dot apply          # deploy dotfiles (secrets from age cache, no prompting)
mse bootstrap          # full bootstrap
mise dot save          # checkpoint tracked files (manual — see note below)
mise dot sync          # push to / pull from origin
```

> **Note on manual saves:** the mise history watcher cannot auto-save in the background because the YubiKey recovery recipient (`age1yubikey1...`) requires an interactive terminal. Run `mise dot save` manually after changes. The watcher process stays running but skips checkpoints it can't encrypt.

## Recovery

If a machine is lost, the encrypted history is recoverable via either recovery recipient:

- **Bitwarden**: retrieve the `mise-age-recovery` secure note, write its contents to a file, set `MISE_AGE_KEY_FILE` to it
- **YubiKey**: plug in the YubiKey, run `mise dot save` (age-plugin-yubikey handles decryption)

The fnox secret cache has no recovery key — if `~/.config/fnox/age.txt` is lost, re-run `fnox sync` / `fnox set` from the original providers (protonpass, bitwarden).

## Sync modes

- **manual** (default): local history checkpoints require manual `mise dot save`; run `mise dot sync` to push/pull
- **sync**: automatic two-way sharing (enable with `mise settings set history.sync sync`)

> With the YubiKey recipient in place, `sync` mode cannot auto-save. Keep `manual`.
