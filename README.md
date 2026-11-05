# wsl-bootstrap

Installs zsh/starship with some plugins and setup git config on fresh WSL.

## What it does

1. Installs apt packages: `zsh git curl fzf starship zoxide eza bat`.
2. Installs oh-my-zsh (official installer, unattended).
3. Clones the plugins `zsh-autosuggestions` and `zsh-syntax-highlighting`.
4. Restores config files from this repo:
   `zshrc` -> `~/.zshrc`, `starship.toml` -> `~/.config/starship.toml`,
   `nanorc` -> `~/.nanorc`, `vimrc` -> `~/.vimrc`.
   Also keeps the clean Starship `tokyo-night` preset as `~/.config/starship.toml.tokyo`.
5. Sets zsh as the default shell (`sudo chsh`).
6. Asks for global git `user.name`, `user.email`, `init.defaultBranch`
   (Enter keeps the current value, an empty answer skips it).
7. Optionally (`--wsl-conf`) writes `/etc/wsl.conf`: systemd, default user,
   hostname (asked), automount with `metadata`.
8. Checks in `zsh -i` that the tools, plugins, zoxide and the Starship prompt work.

Safe to re-run: finished steps are skipped, changed files are backed up as `*.bak-<timestamp>`.

## Usage

Run as your normal user, not root:

```bash
git clone https://github.com/k4zz/wsl-bootstrap.git
bash wsl-bootstrap/bootstrap-zsh.sh --wsl-conf
exec zsh
```

Options:

| Option | Effect |
|---|---|
| `--dry-run` | show what would be done, change nothing, ask nothing |
| `--wsl-conf` | also write `/etc/wsl.conf` (takes effect after `wsl.exe --terminate <distro>`) |
| `--save` | copy the current config files from the system back into the repo, then exit |
| `-h`, `--help` | show help |
