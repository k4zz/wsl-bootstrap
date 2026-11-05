#!/usr/bin/env bash
# Rebuild the desk-wsl zsh terminal on a fresh Ubuntu (WSL).
#
# Installs: zsh, oh-my-zsh + plugins, Starship, fzf, zoxide, eza, bat.
# Restores from this directory: ~/.zshrc, ~/.config/starship.toml, ~/.nanorc, ~/.vimrc.
# Asks for git user.name, user.email and init.defaultBranch.
# Safe to re-run: skips what is already installed, backs up changed files as *.bak-<stamp>.
# Does not touch SSH (keys, ~/.ssh/config), bash config, Hermes or Claude Code.
#
# Usage (as the normal user, not root):
#   git clone https://github.com/k4zz/wsl-bootstrap.git && bash wsl-bootstrap/bootstrap-zsh.sh [options]
#
# Options:
#   --dry-run    show what would be done, change nothing, ask nothing
#   --wsl-conf   also write /etc/wsl.conf (systemd, default user, hostname, automount metadata)
#   --save       copy the current config files from this system back into this directory, then exit
#   -h, --help   show this help

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_PLUGINS="$ZSH_DIR/custom/plugins"
APT_PACKAGES=(zsh git curl fzf starship zoxide eza bat)
# source file in this directory -> destination
declare -A FILES=(
  [zshrc]="$HOME/.zshrc"
  [starship.toml]="$HOME/.config/starship.toml"
  [nanorc]="$HOME/.nanorc"
  [vimrc]="$HOME/.vimrc"
)

DRY_RUN=0
WSL_CONF=0
SAVE=0

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; }

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --wsl-conf) WSL_CONF=1 ;;
    --save) SAVE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '\n==> %s\n' "$*"; }
# run CMD...: execute, or only print it in dry-run mode
# stdin is /dev/null so that apt, sudo and installers never eat the answers meant for the prompts
run() {
  if (( DRY_RUN )); then printf '    [dry-run] %s\n' "$*"; else "$@" </dev/null; fi
}
# ask PROMPT DEFAULT: read an answer from the terminal; Enter keeps DEFAULT
ask() {
  local prompt="$1" default="$2" answer
  if [[ -n "$default" ]]; then prompt="$prompt [$default]"; fi
  read -r -p "$prompt: " answer </dev/tty
  printf '%s' "${answer:-$default}"
}

if [[ $EUID -eq 0 ]]; then
  echo "Run as your normal user (sudo is used where needed)." >&2
  exit 1
fi

# ---------- --save: system -> this directory ----------
if (( SAVE )); then
  log "Saving current config files into $SRC_DIR"
  for f in "${!FILES[@]}"; do
    dst="${FILES[$f]}"
    if [[ ! -f "$dst" ]]; then
      echo "skip $f: $dst does not exist"
    elif cmp -s "$dst" "$SRC_DIR/$f"; then
      echo "same $f"
    else
      [[ -f "$SRC_DIR/$f" ]] && diff -u "$SRC_DIR/$f" "$dst" || true
      run cp "$dst" "$SRC_DIR/$f"
      echo "saved $f"
    fi
  done
  exit 0
fi

# ---------- checks ----------
if ! grep -qi '^ID=ubuntu' /etc/os-release 2>/dev/null; then
  echo "This script expects Ubuntu." >&2
  exit 1
fi
grep -qi microsoft /proc/version 2>/dev/null || echo "Warning: this does not look like WSL; continuing."
for f in "${!FILES[@]}"; do
  [[ -f "$SRC_DIR/$f" ]] || { echo "Missing $SRC_DIR/$f" >&2; exit 1; }
done
(( DRY_RUN )) && echo "Dry run: nothing will be changed."

# ---------- 1. apt packages ----------
log "apt packages"
missing=()
for p in "${APT_PACKAGES[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if (( ${#missing[@]} == 0 )); then
  echo "all installed: ${APT_PACKAGES[*]}"
else
  echo "to install: ${missing[*]}"
  run sudo apt-get update
  run sudo apt-get install -y "${missing[@]}"
fi

# ---------- 2. oh-my-zsh ----------
log "oh-my-zsh"
if [[ -d "$ZSH_DIR" ]]; then
  echo "already present, skipping"
elif (( DRY_RUN )); then
  echo "    [dry-run] install oh-my-zsh (official install.sh, --unattended, KEEP_ZSHRC=yes)"
else
  # KEEP_ZSHRC: our zshrc is restored below; CHSH/RUNZSH: no interactive steps
  env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended </dev/null
fi

# ---------- 3. zsh plugins ----------
log "zsh plugins"
clone_plugin() {
  local name="$1" url="$2"
  if [[ -d "$CUSTOM_PLUGINS/$name" ]]; then
    echo "$name: already present, skipping"
  else
    run git clone --depth 1 "$url" "$CUSTOM_PLUGINS/$name"
  fi
}
clone_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git
clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git

# ---------- 4. config files ----------
log "config files"
restore() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "same: $dst"
    return
  fi
  run mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && cmp -s <(grep -v '^export ZSH=' "$dst") <(grep -v '^export ZSH=' "$ZSH_DIR/templates/zshrc.zsh-template" 2>/dev/null); then
    echo "replacing the oh-my-zsh template (no backup): $dst"
  elif [[ -f "$dst" ]]; then
    run cp "$dst" "$dst.bak-$STAMP"
    echo "backup: $dst.bak-$STAMP"
  fi
  run cp "$src" "$dst"
  echo "restored: $dst"
}
for f in zshrc starship.toml nanorc vimrc; do
  restore "$SRC_DIR/$f" "${FILES[$f]}"
done

# clean tokyo-night preset kept next to the customised one, for reference
TOKYO="$HOME/.config/starship.toml.tokyo"
if [[ -f "$TOKYO" ]]; then
  echo "present: $TOKYO"
else
  run starship preset tokyo-night -o "$TOKYO"
  echo "created: $TOKYO"
fi

# ---------- 5. default shell ----------
log "default shell"
ZSH_BIN="$(command -v zsh || echo /usr/bin/zsh)"
if [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$ZSH_BIN" ]]; then
  echo "already zsh"
else
  # plain chsh failed on desk-wsl, sudo works
  run sudo chsh -s "$ZSH_BIN" "$USER"
fi

# ---------- 6. git ----------
log "git (global)"
git_value() { command -v git >/dev/null && git config --global --get "$1" || true; }
for key in user.name user.email init.defaultBranch; do
  current="$(git_value "$key")"
  if (( DRY_RUN )); then
    echo "$key: would ask (current: ${current:-unset})"
    continue
  fi
  value="$(ask "$key (Enter keeps the value in brackets, empty skips)" "$current")"
  if [[ -z "$value" ]]; then
    echo "$key: skipped"
  elif [[ "$value" == "$current" ]]; then
    echo "$key: unchanged"
  else
    git config --global "$key" "$value"
    echo "$key: set"
  fi
done

# ---------- 7. /etc/wsl.conf (optional) ----------
if (( WSL_CONF )); then
  log "/etc/wsl.conf"
  if (( DRY_RUN )); then
    host="$(hostname)"
    echo "would ask for the hostname (default: $host)"
  else
    host="$(ask "WSL hostname" "$(hostname)")"
  fi
  conf="[boot]
systemd=true

[user]
default=$USER

[network]
hostname = $host

[automount]
options = \"metadata,umask=22,fmask=11\""
  if [[ -f /etc/wsl.conf ]] && [[ "$(cat /etc/wsl.conf)" == "$conf" ]]; then
    echo "same: /etc/wsl.conf"
  else
    [[ -f /etc/wsl.conf ]] && run sudo cp /etc/wsl.conf "/etc/wsl.conf.bak-$STAMP" && echo "backup: /etc/wsl.conf.bak-$STAMP"
    if (( DRY_RUN )); then
      printf '    [dry-run] write /etc/wsl.conf:\n%s\n' "$(sed 's/^/      /' <<<"$conf")"
    else
      printf '%s\n' "$conf" | sudo tee /etc/wsl.conf >/dev/null
      echo "written: /etc/wsl.conf"
    fi
  fi
fi

# ---------- 8. check ----------
if (( ! DRY_RUN )); then
  log "check"
  # shellcheck disable=SC2016
  zsh -i -c '
    ok=1
    for c in zsh starship zoxide eza batcat fzf git; do
      command -v $c >/dev/null && printf "ok   %s\n" $c || { printf "MISS %s\n" $c; ok=0; }
    done
    for p in zsh-autosuggestions zsh-syntax-highlighting; do
      (( ${plugins[(Ie)$p]} )) && [[ -d $ZSH/custom/plugins/$p ]] && printf "ok   plugin %s\n" $p || { printf "MISS plugin %s\n" $p; ok=0; }
    done
    (( $+functions[z] )) && echo "ok   zoxide (z)" || { echo "MISS zoxide init"; ok=0; }
    [[ $PROMPT == *starship* ]] && echo "ok   starship prompt" || { echo "MISS starship prompt"; ok=0; }
    (( ok )) || exit 1
  ' 2>/dev/null </dev/null || { echo "Check failed, see MISS lines above." >&2; exit 1; }
fi

# ---------- 9. manual steps ----------
log "Done. Manual steps:"
cat <<'EOF'
  - Windows: install JetBrainsMono Nerd Font (nerdfonts.com) and set it in the
    Windows Terminal profile of this distribution (Appearance > Font face).
  - Start the new shell: exec zsh (or open a new tab).
  - SSH is not set up by this script. Until ~/.ssh exists, every new shell prints
    "[oh-my-zsh] ssh-agent plugin requires ~/.ssh directory".
EOF
if (( WSL_CONF )); then
  echo "  - /etc/wsl.conf takes effect after: wsl.exe --terminate <distribution> (from Windows or another distribution)."
fi
