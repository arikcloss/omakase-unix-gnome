#!/usr/bin/env bash
# ============================================================================
#  install.sh  —  unixporn·material  "eternal-fedora"  automated installer
#
#  Reproduces the full rice on a FRESH Fedora 44+ / GNOME 48/50 machine:
#    brew/dnf CLI toolbox · JetBrainsMono Nerd Font · Graphite/Tela themes ·
#    GNOME extensions + settings · kitty/fastfetch/starship dotfiles · custom
#    sys* commands · dnf hardening · snapper btrfs snapshots · grub-btrfs ·
#    material GRUB (wolf) with forced-visible menu · Flathub apps · backup.
#
#  Assets (optional, auto-detected next to this script):
#      ascii-text.txt  -> fastfetch logo          (scaled automatically)
#      unix_wolf.jpg   -> wallpaper + GRUB background
#
#  Usage:
#      ./install.sh                run everything (default)
#      ./install.sh --no-flatpaks  skip the Flathub app layer
#      ./install.sh --no-safeguards  skip snapshot/GRUB system work
#      ./install.sh --tools --configs   run only those steps
#
#  Re-running is safe: every step is idempotent.
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_ASCII="$SCRIPT_DIR/assets/ascii-text.txt"
[ -f "$ASSET_ASCII" ] || ASSET_ASCII="$SCRIPT_DIR/ascii-text.txt"
ASSET_WOLF="$SCRIPT_DIR/assets/unix_wolf.jpg"
[ -f "$ASSET_WOLF" ] || ASSET_WOLF="$SCRIPT_DIR/unix_wolf.jpg"
ASSET_GRUB_WOLF="$SCRIPT_DIR/assets/grub_unix_wolf.jpg"
[ -f "$ASSET_GRUB_WOLF" ] || ASSET_GRUB_WOLF="$SCRIPT_DIR/grub_unix_wolf.jpg"
[ -f "$ASSET_GRUB_WOLF" ] || ASSET_GRUB_WOLF="$ASSET_WOLF"

declare -A DO=(
  [tools]=1 [fonts]=1 [themes]=1 [extensions]=1
  [configs]=1 [safeguards]=1 [flatpaks]=1
)

usage() {
  sed -n '5,20p' "$0" | sed -e 's/^# //1' | grep -v '^#$'
  exit 0
}

for a in "$@"; do
  case "$a" in
    --no-tools)      DO[tools]=0 ;;
    --no-fonts)      DO[fonts]=0 ;;
    --no-themes)     DO[themes]=0 ;;
    --no-extensions) DO[extensions]=0 ;;
    --no-configs)    DO[configs]=0 ;;
    --no-safeguards) DO[safeguards]=0 ;;
    --no-flatpaks)   DO[flatpaks]=0 ;;
    --tools)         for k in "${!DO[@]}"; do DO[$k]=0; done; DO[tools]=1 ;;
    --fonts)         for k in "${!DO[@]}"; do DO[$k]=0; done; DO[fonts]=1 ;;
    --themes)        for k in "${!DO[@]}"; do DO[$k]=0; done; DO[themes]=1 ;;
    --extensions)    for k in "${!DO[@]}"; do DO[$k]=0; done; DO[extensions]=1 ;;
    --configs)       for k in "${!DO[@]}"; do DO[$k]=0; done; DO[configs]=1 ;;
    --safeguards)    for k in "${!DO[@]}"; do DO[$k]=0; done; DO[safeguards]=1 ;;
    --flatpaks)      for k in "${!DO[@]}"; do DO[$k]=0; done; DO[flatpaks]=1 ;;
    -h|--help)       usage ;;
    *) echo "unknown option: $a" >&2; usage ;;
  esac
done

# ---- tiny ui helpers -------------------------------------------------------
C_B=$'\033[1;34m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_0=$'\033[0m'
section() { printf '\n%s=== %s ===%s\n' "$C_B" "$*" "$C_0"; }
info()    { printf '  %s%s%s\n' "$C_G" "$*" "$C_0"; }
warn()    { printf '  %s! %s%s\n' "$C_Y" "$*" "$C_0" >&2; }
fail()    { printf '  %s!! %s%s\n' "$C_R" "$*" "$C_0" >&2; exit 1; }
have()    { command -v "$1" >/dev/null 2>&1; }

# ---- preflight --------------------------------------------------------------
section "preflight"
if [ "$(id -u)" -eq 0 ]; then
  fail "do not run as root - run as your normal user (sudo is prompted internally)"
fi
grep -q '^ID=fedora' /etc/os-release 2>/dev/null || warn "not Fedora — continuing, some steps may differ"
sudo -v || fail "sudo required"
have git     || fail "please install git:  sudo dnf install -y git"
have curl    || { info "installing curl"; sudo dnf install -y curl >/dev/null 2>&1; }
have python3 || fail "please install python3"

GVER="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
GVER="${GVER:-48}"
info "GNOME shell major: $GVER  |  user: $USER  |  scripts dir: $SCRIPT_DIR"
WORK="$(mktemp -d /tmp/etf-install.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# ==============================================================================
# 1 · CLI toolbox  (Homebrew primary, dnf fallback)
# ==============================================================================
if [ "${DO[tools]}" = 1 ]; then
  section "CLI toolbox"

  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    info "using Homebrew (/home/linuxbrew/.linuxbrew)"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    for p in kitty fastfetch starship eza bat fzf ripgrep fd zoxide tlrc bottom lazygit gh sassc; do
      if ! have "$p"; then
        "$(command -v brew)" install "$p" >/dev/null 2>&1 && info "  + $p (brew)" || warn "  - $p brew install failed"
      else
        info "  = $p"
      fi
    done
  else
    info "no Homebrew — falling back to dnf"
    for p in kitty fastfetch starship eza bat fzf ripgrep fd-find zoxide tlrc bottom lazygit gh sassc; do
      if ! have "$p" && ! have "${p/fd-find/fd}"; then
        sudo dnf install -y "$p" >/dev/null 2>&1 && info "  + $p (dnf)" || warn "  - $p not in dnf (install manually)"
      else
        info "  = $p"
      fi
    done
  fi
  command -v tldr >/dev/null 2>&1 || command -v tlrc >/dev/null 2>&1 || warn "  man pages: install tlrc for 'tldr'"
fi

# ==============================================================================
# 2 · JetBrains Mono Nerd Font  (kitty + terminal UIs)
# ==============================================================================
if [ "${DO[fonts]}" = 1 ]; then
  section "JetBrainsMono Nerd Font"
  if fc-list 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd'; then
    info "already installed"
  else
    have unzip || { info "installing unzip"; sudo dnf install -y unzip >/dev/null 2>&1; }
    if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip" -o "$WORK/JetBrainsMono.zip"; then
      mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
      unzip -oq "$WORK/JetBrainsMono.zip" -d "$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
      fc-cache -f >/dev/null 2>&1
      info "installed + fc-cache refreshed"
    else
      warn "font download failed - install JetBrainsMono Nerd Font manually"
    fi
  fi
fi

# ==============================================================================
# 3 · Themes  (Graphite GTK + Tela icons + Graphite cursors + wallpaper)
# ==============================================================================
if [ "${DO[themes]}" = 1 ]; then
  section "Graphite/Tela themes"
  have sassc || { info "installing sassc"; sudo dnf install -y sassc >/dev/null 2>&1; }

  if [ ! -d "$HOME/.themes/Graphite-Dark" ]; then
    git clone --depth 1 https://github.com/vinceliuice/Graphite-gtk-theme "$WORK/Graphite" >/dev/null 2>&1
    ( cd "$WORK/Graphite" && ./install.sh -c dark --tweaks black float --round 10 -l >/dev/null 2>&1 ) && \
      info "  + Graphite-Dark (gtk/shell/libadwaita)" || warn "  Graphite install failed (sassc?)"
  else
    info "  = Graphite-Dark"
  fi

  if [ ! -d "$HOME/.local/share/icons/Tela-circle-black" ]; then
    git clone --depth 1 https://github.com/vinceliuice/Tela-circle-icon-theme "$WORK/Tela" >/dev/null 2>&1
    ( cd "$WORK/Tela" && ./install.sh -d "$HOME/.local/share/icons" black >/dev/null 2>&1 ) && \
      info "  + Tela-circle-black icons" || warn "  Tela icons install failed"
  else
    info "  = Tela-circle-black"
  fi

  if [ ! -d "$HOME/.local/share/icons/Graphite-Dark" ]; then
    git clone --depth 1 https://github.com/vinceliuice/Graphite-cursors "$WORK/Cursors" >/dev/null 2>&1
    if [ -d "$WORK/Cursors/dist-dark" ]; then
      cp -r "$WORK/Cursors/dist-dark" "$HOME/.local/share/icons/Graphite-Dark"
      info "  + Graphite-Dark cursors"
    else
      warn "  Graphite cursors: dist-dark not found - run Graphite-cursors/install.sh manually"
    fi
  else
    info "  = Graphite-Dark cursors"
  fi

  # wallpaper + desktop appearance
  if [ -f "$ASSET_WOLF" ]; then
    mkdir -p "$HOME/.local/share/backgrounds"
    cp "$ASSET_WOLF" "$HOME/.local/share/backgrounds/unix-wolf.jpg"
    gsettings set org.gnome.desktop.background picture-uri     "file://$HOME/.local/share/backgrounds/unix-wolf.jpg"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/.local/share/backgrounds/unix-wolf.jpg"
    gsettings set org.gnome.desktop.screensaver picture-uri     "file://$HOME/.local/share/backgrounds/unix-wolf.jpg"
    gsettings set org.gnome.desktop.background picture-options 'zoom'
    info "  + wallpaper unix-wolf.jpg"
  else
    warn "  no unix_wolf.jpg next to install.sh - wallpaper skipped"
  fi

  gsettings set org.gnome.desktop.interface gtk-theme    'Graphite-Dark'   2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme   'Tela-circle-black' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme 'Graphite-Dark'   2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface font-name    'Cantarell 11'
  info "  + gsettings: Graphite-Dark / Tela-circle-black / prefer-dark"
fi

# ==============================================================================
# 4 · GNOME extensions  (from extensions.gnome.org) + settings
# ==============================================================================
if [ "${DO[extensions]}" = 1 ]; then
  section "GNOME extensions"
  have gnome-extensions || fail "gnome-extensions not found"
  have dconf  || { info "installing dconf";  sudo dnf install -y dconf  >/dev/null 2>&1; }
  have unzip  || { info "installing unzip";  sudo dnf install -y unzip  >/dev/null 2>&1; }

  ego() { # <pk> <uuid>
    local pk="$1" uuid="$2" url
    url="$(curl -fsS "https://extensions.gnome.org/extension-info/?pk=$pk&shell_version=$GVER" \
            | python3 -c 'import json,sys;print(json.load(sys.stdin)["download_url"])' 2>/dev/null)" || return 1
    curl -fsSL "https://extensions.gnome.org$url" -o "$WORK/$uuid.zip" || return 1
    gnome-extensions install --force "$WORK/$uuid.zip" >/dev/null 2>&1 || return 1
  }

  ext() { # <pk> <uuid>
    if gnome-extensions show "$2" >/dev/null 2>&1; then info "  = $2"; return; fi
    if ego "$1" "$2"; then info "  + $2"; else warn "  ! $2 failed (network or unsupported shell $GVER)"; fi
  }

  ext 3193 blur-my-shell@aunetx
  ext 307  dash-to-dock@micxgx.gmail.com
  ext 3628 arcmenu@arcmenu.com
  ext 3843 just-perfection-desktop@just-perfection
  ext 19   user-theme@gnome-shell-extensions.gcampax.github.com
  ext 615  appindicatorsupport@rgcjonas.gmail.com
  ext 4679 burn-my-windows@schneegans.github.com
  ext 1460 Vitals@CoreCoding.com
  ext 5410 grand-theft-focus@zalckos.github.com
  ext 4269 AlphabeticalAppGrid@stuarthayhurst

  gsettings set org.gnome.shell enabled-extensions \
    "['AlphabeticalAppGrid@stuarthayhurst', 'appindicatorsupport@rgcjonas.gmail.com', 'arcmenu@arcmenu.com', 'blur-my-shell@aunetx', 'burn-my-windows@schneegans.github.com', 'dash-to-dock@micxgx.gmail.com', 'grand-theft-focus@zalckos.github.com', 'just-perfection-desktop@just-perfection', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'Vitals@CoreCoding.com']" 2>/dev/null || true

  # exact golden-set settings, applied as a dconf dump (types stay correct)
  dconf load /org/gnome/shell/extensions/ <<'DCONF_DUMP'
[Vitals]
hide-gpu=true
position-in-panel=2

[arc-menu]
menu-button-icon='fedora'
menu-button-text='Fedora'
menu-layout='simple'

[arcmenu]
menu-button-icon='resource:///org/gnome/shell/extensions/arcmenu/icons/scalable/actions/distro-fedora.svg'
prefs-visible-page=0
search-entry-border-radius=(true, 25)
update-notifier-project-version=73

[blur-my-shell]
blur-onlockscreen=true
rounded-blur-found=false
settings-version=2

[blur-my-shell/appfolder]
blur=true
brightness=0.6
opacity=200
radius=20
sigma=30

[blur-my-shell/dash-to-dock]
blur=true
brightness=0.6
sigma=30
static-blur=true
style-dash-to-dock=0

[blur-my-shell/dash]
blur=false
opacity=170
radius=20
static-blur=true

[blur-my-shell/overview]
blur=true
opacity=210
radius=18
static-blur=false

[blur-my-shell/panel]
blur=true
brightness=0.6
corner-radius=0
opacity=190
radius=18
sigma=30
static-blur=false

[blur-my-shell/window-list]
brightness=0.6
sigma=30

[blur-my-shell/window]
blur=false

[burn-my-windows]
animation-name='hexagon'
last-extension-version=48

[dash-to-dock]
animations=true
autohide=true
autohide-in-fullscreen=true
background-color='rgb(0,0,0)'
background-opacity=0.75
custom-background-color=true
custom-theme-shrink=false
dash-max-icon-size=42
dock-fixed=true
dock-position='BOTTOM'
extend-height=false
height-fraction=0.9
intellihide=false
preferred-monitor=-2
preferred-monitor-by-connector='HDMI-1'
show-apps-at-top=false
show-trash=false
transparency-mode='FIXED'

[grand-theft-focus]
gtf-active-border-color='#61afef'
gtf-active-window-border-width=2
gtf-enable=true

[just-perfection]
activities-button=false
animation=0
app-menu=false
panel-notification-icon=false
search=false
weather=false
window-menu=false
world-clock=false

[user-theme]
name='Graphite-Dark'
DCONF_DUMP
  info "settings applied - extensions activate on next login"
fi

# ==============================================================================
# 5 · Dotfiles & configs
# ==============================================================================
if [ "${DO[configs]}" = 1 ]; then
  section "dotfiles & configs"

  CONF="$HOME/.config"
  mkdir -p "$CONF/kitty" "$CONF/fastfetch" "$CONF/eternal-fedora" "$HOME/.local/bin"
  KITTY_BIN="$(command -v kitty || echo /usr/bin/kitty)"

  # ---- kitty ---------------------------------------------------------------
  cat > "$CONF/kitty/kitty.conf" <<'KITTY_CONF'
# unixporn·material kitty
font_family              JetBrainsMono Nerd Font Mono
font_size                12.0
adjust_line_height       0
adjust_column_width      0%

window_padding_width     10
hide_window_decorations  titlebar-only
placement_strategy       center
remember_window_size     yes
initial_window_width     1100
initial_window_height    640

background_opacity       0.90
dynamic_background_opacity   no

background               #20242b
foreground               #d7dbe2
selection_background     #3a4150
selection_foreground     #ffffff

color0                   #2f3640
color1                   #e06c75
color2                   #98c379
color3                   #d19a66
color4                   #61afef
color5                   #c678dd
color6                   #56b6c2
color7                   #abb2bf
color8                   #566070
color9                   #e06c75
color10                  #98c379
color11                  #d19a66
color12                  #61afef
color13                  #c678dd
color14                  #56b6c2
color15                  #d7dbe2

active_border_color      #61afef
inactive_border_color    #2f3640
bell_border_color        #d19a66

cursor                   #61afef
cursor_text_color        #20242b
mark1_foreground         #20242b
mark1_background         #61afef

tab_bar_style            separator
tab_bar_edge              top
tab_bar_min_tabs          2
active_tab_foreground     #ffffff
active_tab_background     #3a4150
inactive_tab_foreground   #abb2bf
inactive_tab_background   #20242b
tab_bar_margin_width     0.0

scrollback_lines         10000
scrollback_pager         less --chop-long-lines --clear-screen

enabled_layouts          splits,stack
shell_integration        enabled
copy_on_select           clipboard
confirm_os_window_close  0
cursor_shape             beam
cursor_blink_interval    0
KITTY_CONF
  info "  + kitty.conf"

  gsettings set org.gnome.desktop.default-applications.terminal exec "$KITTY_BIN" 2>/dev/null || true

  cat > "$HOME/.local/share/applications/kitty.desktop" <<EOF
[Desktop Entry]
Name=kitty
Comment=The fast, feature-rich, GPU based terminal emulator
Exec=$KITTY_BIN
Icon=kitty
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
EOF

  # ---- fastfetch logo (scaled + two-tone shading from ascii-text.txt) ------
  mkdir -p "$WORK"
  cat > "$WORK/mklogo.py" <<'PY'
import os
def recolor(line):
    ramp_dark = set("#%@+*=")
    ramp_lite = set("-:.")
    out, cur = [], ""
    for ch in line:
        nxt = "\x1b[37m" if ch in ramp_dark else ("\x1b[38;5;244m" if ch in ramp_lite else "\x1b[0m")
        if nxt != cur:
            out.append(nxt); cur = nxt
        out.append(ch)
    out.append("\x1b[0m")
    return "".join(out)
def main():
    import sys
    infile, outfile = sys.argv[1], sys.argv[2]
    maxh = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    maxw = int(sys.argv[4]) if len(sys.argv) > 4 else 44
    lines = [l.rstrip("\n") for l in open(infile)]
    while lines and not lines[0].strip(): lines.pop(0)
    while lines and not lines[-1].strip(): lines.pop()
    h, w = len(lines), max(len(l) for l in lines)
    def idx(n, t):
        return sorted({round((n-1)*i/(t-1)) if t > 1 else 0 for i in range(t)})
    if h > maxh:
        rows = [lines[i] for i in idx(h, maxh)]
    else:
        rows = lines
    if w > maxw:
        ci = set(idx(w, maxw))
        rows = ["".join(c for i, c in enumerate(r) if i in ci) for r in rows]
    rows = [r.rstrip() for r in rows]
    while rows and not rows[0].strip(): rows.pop(0)
    while rows and not rows[-1].strip(): rows.pop()
    open(outfile, "w").write("\n".join(recolor(r) for r in rows) + "\n")
if __name__ == "__main__":
    main()
PY

  if [ -f "$ASSET_ASCII" ]; then
    python3 "$WORK/mklogo.py" "$ASSET_ASCII" "$CONF/fastfetch/logo.txt" \
      && info "  + fastfetch logo (scaled from ascii-text.txt)" || warn "  logo scaling failed"
  else
    cat > "$CONF/fastfetch/logo.txt" <<'FALLBACK'
    ________
   /  .---.  \
  /  /     \  \
  |  |  o o |  |
  |  |  \_/ |  |
   \  \_____/  /
    \_________/
FALLBACK
    warn "  no ascii-text.txt next to install.sh - using fallback logo"
  fi

  cat > "$CONF/fastfetch/config.jsonc" <<'FF_CONF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "file",
    "source": "$HOME/.config/fastfetch/logo.txt",
    "color": { "1": "37", "2": "7" },
    "padding": { "right": 3 }
  },
  "display": {
    "separator": "  ",
    "key": { "width": 10, "color": "blue" }
  },
  "modules": [
    { "type": "title",       "format": "unix-wolf \u00b7 fedora", "color": "blue" },
    { "type": "separator" },
    { "type": "os" },
    { "type": "kernel" },
    { "type": "uptime" },
    { "type": "packages" },
    { "type": "shell" },
    { "type": "wm" },
    { "type": "de" },
    { "type": "terminal",    "key": "Term" },
    { "type": "display" },
    { "type": "cpu" },
    { "type": "gpu" },
    { "type": "memory" },
    { "type": "disk" },
    { "type": "break" },
    { "type": "colors",      "symbol": "block" },
    { "type": "break" }
  ]
}
FF_CONF
  info "  + fastfetch config"

  # ---- starship ------------------------------------------------------------
  cat > "$CONF/starship.toml" <<'STARSHIP_CONF'
# unixporn·material starship
add_newline        = true
scan_timeout       = 10

[character]
success_symbol = "[❯](bold blue)"
error_symbol   = "[❯](bold red)"

[directory]
style        = "bold fg-blue"
read_only    = " 󰌾"
truncation_length = 4
truncate_to_repo = false

[git_branch]
symbol     = " "
style      = "bold cyan"
format     = "on [$symbol$branch(:$remote_branch)]($style) "

[git_status]
style = "bold yellow"

[cmd_duration]
min_time = 2000
style    = "dimmed yellow"
format   = "took [$duration]($style) "

[nodejs]
symbol    = "  "
style     = "bold green"
format    = "via [$symbol($version)]($style) "

[python]
symbol    = " "
style     = "bold yellow"
format    = "via [$symbol($version)]($style) "

[bun]
symbol    = " "
style     = "bold magenta"
format    = "via [$symbol($version)]($style) "

[rust]
symbol    = " "
style     = "bold red"
format    = "via [$symbol($version)]($style) "

[golang]
symbol    = "  "
style     = "bold cyan"
format    = "via [$symbol($version)]($style) "

[package]
style = "bold blue"
format = "📦 [$version](bold blue) "

[username]
show_always = false

[hostname]
ssh_only = true
STARSHIP_CONF
  info "  + starship config"

  # ---- eternal-fedora shell environment ------------------------------------
  cat > "$CONF/eternal-fedora/env.sh" <<'ENV_CONF'
# eternal-fedora shell environment (sourced from ~/.bashrc)
case $- in *i*) ;; *) return ;; esac

# brew (CLI toolbox + kitty/fastfetch live here if installed)
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
export PATH="$HOME/.local/bin:$PATH"

# modern command replacements
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first --git'
alias la='eza -a --icons'
alias tree='eza --tree --icons'
alias cat='bat --paging=never'
alias grep='rg'
alias find='fd'
alias fetch='fastfetch'
alias ff='fastfetch'
alias upd='sysupdate'
alias fix='sysfix'
alias clean='sysclean'
alias snap='syssnap'
alias rollback='sysrollback'
alias bk='backup-dots'

export BAT_THEME='Monokai Extended'
export EDITOR='vim'
export MANPAGER='sh -c "col -bx | bat -l man -p"'

# fzf bindings (brew or dnf paths)
[ -f /home/linuxbrew/.linuxbrew/opt/fzf/shell/completion.bash ] && source /home/linuxbrew/.linuxbrew/opt/fzf/shell/completion.bash
[ -f /home/linuxbrew/.linuxbrew/opt/fzf/shell/key-bindings.bash ]  && source /home/linuxbrew/.linuxbrew/opt/fzf/shell/key-bindings.bash
[ -f /usr/share/bash-completion/completions/fzf ] && source /usr/share/bash-completion/completions/fzf 2>/dev/null || true
[ -f /usr/share/doc/fzf/shell/completion.bash ] && source /usr/share/doc/fzf/shell/completion.bash 2>/dev/null || true
[ -f /usr/share/doc/fzf/shell/key-bindings.bash ] && source /usr/share/doc/fzf/shell/key-bindings.bash 2>/dev/null || true
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git --exclude node_modules'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# zoxide + starship
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"

# gh completions
type gh >/dev/null 2>&1 && eval "$(gh completion -s bash 2>/dev/null)"

[ -f "$HOME/.config/eternal-fedora/motd.sh" ] && . "$HOME/.config/eternal-fedora/motd.sh"
ENV_CONF
  info "  + eternal-fedora/env.sh"

  cat > "$CONF/eternal-fedora/motd.sh" <<'MOTD'
if [ -z "${ETF_MOTD_SHOWN:-}" ]; then
  export ETF_MOTD_SHOWN=1
  echo "   * eternal-fedora environment loaded — try: sysupdate · sysfix · sysclean · fetch"
fi
MOTD

  # idempotent ~/.bashrc loader
  if ! grep -q 'eternal-fedora/env.sh' "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'BASHRC'

# eternal-fedora (managed by install.sh)
if [ -f "$HOME/.config/eternal-fedora/env.sh" ]; then
    . "$HOME/.config/eternal-fedora/env.sh"
fi
BASHRC
    info "  + ~/.bashrc loader appended"
  else
    info "  = ~/.bashrc already wired"
  fi

  # ---- custom commands ------------------------------------------------------
  write_cmd() { cat > "$HOME/.local/bin/$1"; chmod +x "$HOME/.local/bin/$1"; }

  write_cmd sysupdate <<'SYS_UPDATE'
#!/usr/bin/env bash
# sysupdate — full refresh: safety snapshot, dnf + flatpak + brew
set -u
echo "== [sysupdate] safety snapshot =="
if command -v snapper >/dev/null 2>&1; then
  sudo snapper -c root create -d "before update" -t single 2>/dev/null || true
  sudo snapper -c home create -d "before update" -t single 2>/dev/null || true
else
  echo "  (snapper not installed yet — run: sudo dnf install snapper)"
fi
echo "== [sysupdate] dnf upgrade (keepcache on) =="
sudo dnf upgrade --refresh -y --setopt=keepcache=True || exit 1
echo "== [sysupdate] flatpak update =="
flatpak update -y 2>/dev/null || echo "  (no flatpak or nothing to do)"
echo "== [sysupdate] brew update + upgrade =="
brew update 2>/dev/null || true
brew upgrade 2>/dev/null || true
brew cleanup 2>/dev/null || true
echo "== [sysupdate] refresh caches =="
sudo dnf makecache 2>/dev/null || true
echo
echo "Done. If the kernel was updated, reboot:  sudo reboot"
SYS_UPDATE

  write_cmd sysfix <<'SYS_FIX'
#!/usr/bin/env bash
# sysfix — repair broken bits: rpm db, dnf caches, flatpak, grub menu, icons/fonts
set -u
echo "== [sysfix] rpm database =="
sudo rpm --rebuilddb 2>/dev/null && echo "  rpm db rebuilt"
echo "== [sysfix] dnf caches =="
sudo dnf clean all 2>/dev/null || true
sudo dnf makecache 2>/dev/null || true
echo "== [sysfix] dnf consistency check =="
sudo dnf check 2>&1 | tail -5 || true
echo "== [sysfix] flatpak repair =="
flatpak repair --user 2>/dev/null || flatpak repair 2>/dev/null || true
echo "== [sysfix] regenerate GRUB menu (snapshots + theme) =="
if command -v grub2-mkconfig >/dev/null 2>&1; then
  sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || echo "  (skipped — run manually: sudo grub2-mkconfig -o /boot/grub2/grub.cfg)"
fi
echo "== [sysfix] font + icon caches =="
fc-cache -f >/dev/null 2>&1 || true
find ~/.local/share/icons -name icon-theme.cache -exec gtk-update-icon-cache -f {} + 2>/dev/null || true
echo "== [sysfix] systemd unit state =="
systemctl daemon-reload 2>/dev/null || true
echo "Done."
SYS_FIX

  write_cmd sysclean <<'SYS_CLEAN'
#!/usr/bin/env bash
# sysclean — tidy up: orphans, caches, old journal, unused flatpaks, brew cruft
set -u
echo "== [sysclean] dnf orphans =="
sudo dnf autoremove -y 2>&1 | tail -3
sudo dnf clean all 2>/dev/null || true
echo "== [sysclean] old journal (keep 7 days) =="
sudo journalctl --vacuum-time=7d 2>/dev/null | tail -2 || true
echo "== [sysclean] flatpak =="
flatpak uninstall --unused -y 2>/dev/null || true
flatpak remove --unused 2>/dev/null || true
echo "== [sysclean] brew =="
brew cleanup -s 2>/dev/null || true
brew autoremove 2>/dev/null || true
echo "== [sysclean] tmp cleanup =="
sudo systemd-tmpfiles --clean 2>/dev/null || true
echo "Done. Disk reclaimed:"; df -h / /home 2>/dev/null
SYS_CLEAN

  write_cmd syssnap <<'SYS_SNAP'
#!/usr/bin/env bash
# syssnap — take btrfs snapshots (root + home) via snapper and list them.
# Usage: syssnap [quiet]
set -u
QUIET="${1:-}"
if ! command -v snapper >/dev/null 2>&1; then
  echo "snapper is not installed. Set it up first:"
  echo "  sudo dnf install snapper"
  echo "  sudo snapper -c root create-config /"
  echo "  sudo snapper -c home create-config /home"
  exit 1
fi
[ -n "$QUIET" ] || echo "== [syssnap] creating snapshots =="
sudo snapper -c root create -d "manual snapshot $(date +%F_%T)" -t single 2>/dev/null || echo "  root snapshot failed (config 'root' missing?)"
sudo snapper -c home create -d "manual snapshot $(date +%F_%T)" -t single 2>/dev/null || echo "  home snapshot failed (config 'home' missing?)"
[ -n "$QUIET" ] || echo "== [syssnap] latest snapshots =="
if command -v snapper >/dev/null 2>&1; then
  sudo snapper -c root list 2>/dev/null | tail -5
  sudo snapper -c home list 2>/dev/null | tail -5
fi
[ -n "$QUIET" ] || echo "Boot into any snapshot from the GRUB 'Snapshots' submenu."
SYS_SNAP

  write_cmd sysrollback <<'SYS_ROLLBACK'
#!/usr/bin/env bash
# sysrollback — recover from a bad state using btrfs snapshots.
set -u
echo "== [sysrollback] available snapshots =="
if command -v snapper >/dev/null 2>&1; then
  sudo snapper -c root list 2>/dev/null | head -25
else
  echo "snapper not installed."
fi
echo
echo "How to roll back:"
echo "  1. Preferred: reboot, and in the GRUB menu open 'Snapshots' and pick the"
echo "     snapshot taken before the problem. System boots into that state."
echo "  2. From here:  sudo snapper -c root rollback <number> && sudo reboot"
echo "     (rollback of 'root' is safe; 'home' snapshots can abort if files are in use)."
SYS_ROLLBACK

  write_cmd sysupgrade-major <<'SYS_UPGRADE'
#!/usr/bin/env bash
# sysupgrade-major — upgrade Fedora to the next release safely (eternal fedora).
# Usage:  sysupgrade-major 42
set -u
RELEASE="${1:-}"
if [ -z "$RELEASE" ]; then
  echo "Usage: sudo sysupgrade-major <release-version>   (e.g. sysupgrade-major 45)"
  exit 1
fi
echo "== [sysupgrade-major] pre-flight backup + snapshot =="
backup-dots >/dev/null 2>&1 || true
command -v snapper >/dev/null 2>&1 && { sudo snapper -c root create -d "before upgrade ${RELEASE}" -t single || true; }
echo "== [sysupgrade-major] fetching packages for release ${RELEASE} =="
sudo dnf system-upgrade download --releasever="$RELEASE" --setopt=keepcache=True --allowerasing
echo
echo "Review the output above, then reboot into the upgrade:"
echo "  sudo dnf system-upgrade reboot"
echo
echo "If anything looks wrong, reboot now and pick an older snapshot from GRUB."
SYS_UPGRADE

  write_cmd backup-dots <<'BACKUP_DOTS'
#!/usr/bin/env bash
# backup-dots — snapshot every dotfile/config this rice touches (and OS-level
# settings) into ~/Backups/dotfiles/<timestamp>, plus a tar.gz copy in the
# project folder. Part of eternal-fedora.
set -u
PROJECT_DIR="${ETF_PROJECT_DIR:-$HOME/Documentos/Default Project}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Backups/dotfiles/$STAMP"
mkdir -p "$BACKUP_DIR"/{home-config,eternal-fedora,fonts,os-info}
mkdir -p "$BACKUP_DIR/system-configs/etc/snapper/configs" \
         "$BACKUP_DIR/system-configs/etc/default" \
         "$BACKUP_DIR/system-configs/etc/grub.d" \
         "$BACKUP_DIR/system-configs/etc/dnf"
echo "== [backup-dots] $BACKUP_DIR =="
for p in fastfetch kitty starship eternal-fedora gtk-4.0 gtk-3.0; do
  [ -e "$HOME/.config/$p" ] && cp -r "$HOME/.config/$p" "$BACKUP_DIR/home-config/"
done
[ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$BACKUP_DIR/home-config/"
[ -f "$HOME/.bash_profile" ] && cp "$HOME/.bash_profile" "$BACKUP_DIR/home-config/"
[ -d "$HOME/.themes/Graphite-Dark" ] && cp -r "$HOME/.themes/Graphite-Dark" "$BACKUP_DIR/home-config/"
[ -d "$HOME/.local/share/icons/Graphite-Dark" ] && cp -r "$HOME/.local/share/icons/Graphite-Dark" "$BACKUP_DIR/home-config/"
echo "Tela-circle-black: git clone https://github.com/vinceliuice/Tela-circle-icon-theme && ./install.sh -d ~/.local/share/icons black" > "$BACKUP_DIR/home-config/icons-install.txt"
[ -f "$HOME/.local/share/backgrounds/unix-wolf.jpg" ] && cp "$HOME/.local/share/backgrounds/unix-wolf.jpg" "$BACKUP_DIR/home-config/"
dconf dump / > "$BACKUP_DIR/eternal-fedora/dconf-full.txt" 2>/dev/null || true
gsettings list-recursively org.gnome.desktop 2>/dev/null > "$BACKUP_DIR/eternal-fedora/gnome-desktop.txt" || true
gsettings list-recursively org.gnome.shell 2>/dev/null   > "$BACKUP_DIR/eternal-fedora/gnome-shell.txt"  || true
for f in /etc/dnf/dnf.conf /etc/default/grub /etc/snapper/configs/root /etc/snapper/configs/home /etc/fstab /etc/grub-btrfs/config /etc/hostname; do
  [ -r "$f" ] 2>/dev/null && sudo cat "$f" > "$BACKUP_DIR/system-configs${f}" 2>/dev/null
done
[ -f /etc/grub.d/10_linux ] && sudo cp /etc/grub.d/10_linux "$BACKUP_DIR/system-configs/etc/grub.d/10_linux" 2>/dev/null
ARCHIVE="$HOME/Backups/dotfiles/backup-$STAMP.tar.gz"
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" . 2>/dev/null
mkdir -p "$PROJECT_DIR" 2>/dev/null
cp "$ARCHIVE" "$PROJECT_DIR/backup-$STAMP.tar.gz" 2>/dev/null && echo "  copy -> $PROJECT_DIR/backup-$STAMP.tar.gz"
echo "Done. Folder:  $BACKUP_DIR"
echo "Archive:      $ARCHIVE"
BACKUP_DOTS

  info "  + sysupdate · sysfix · sysclean · syssnap · sysrollback · sysupgrade-major · backup-dots"
fi

# ==============================================================================
# 6 · Eternal-Fedora safeguards  (dnf hardening · auto-updates · snapper ·
#     grub-btrfs · material GRUB with forced-visible menu)
# ==============================================================================
if [ "${DO[safeguards]}" = 1 ]; then
  section "eternal-fedora safeguards (root steps)"
  sudo -v

  # ---- dnf hardening ---------------------------------------------------------
  sudo tee /etc/dnf/dnf.conf >/dev/null <<'DNF_CONF'
# see `man dnf.conf` for defaults and possible options

[main]

# eternal-fedora: keeps cache for offline rollback, faster + safer updates
keepcache=True
max_parallel_downloads=10
fastestmirror=True
installonly_limit=5
check_imported_gpgkey=True
DNF_CONF
  info "  + /etc/dnf/dnf.conf hardened (keepcache, 5 kernels, parallel 10)"

  # ---- auto security updates -------------------------------------------------
  sudo dnf install -y dnf5-plugin-automatic chrony make inotify-tools snapper btrfs-assistant ImageMagick unzip sassc >/dev/null 2>&1 \
    || warn "  some packages failed to install (check network/repos)"
  sudo tee /etc/dnf/automatic.conf >/dev/null <<'AUTOMATIC_CONF'
# eternal-fedora: auto-apply only SECURITY updates daily, never reboot by itself
[commands]
apply_updates = yes
download_updates = yes
upgrade_type = security
reboot = never
AUTOMATIC_CONF
  systemctl enable --now dnf5-automatic.timer 2>/dev/null || systemctl enable --now dnf-automatic.timer 2>/dev/null || true
  systemctl enable --now fstrim.timer 2>/dev/null || true
  systemctl enable --now chronyd 2>/dev/null || true
  info "  + auto security updates + fstrim + chrony timers"

  # ---- snapper btrfs snapshots ------------------------------------------------
  if command -v snapper >/dev/null 2>&1; then
    snapper list-configs 2>/dev/null | grep -q '^root ' || sudo snapper -c root create-config / >/dev/null 2>&1
    if [ -d /home/.snapshots ] || mountpoint -q /home; then
      snapper list-configs 2>/dev/null | grep -q '^home ' || sudo snapper -c home create-config /home >/dev/null 2>&1
    fi
    for CONF_NAME in root home; do
      F="/etc/snapper/configs/$CONF_NAME"
      [ -f "$F" ] && {
        sudo sed -i '/^TIMELINE_/d' "$F"
        sudo tee -a "$F" >/dev/null <<EOF
TIMELINE_CREATE="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="5"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="2"
TIMELINE_LIMIT_YEARLY="0"
EOF
      }
    done
    systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
    info "  + snapper (root+home) with auto-timeline"
  else
    warn "  snapper not available — skipping snapshots"
  fi

  # ---- grub-btrfs (boot snapshots from the GRUB menu) --------------------------
  if ! command -v grub-btrfsd >/dev/null 2>&1; then
    git clone --depth 1 https://github.com/Antynea/grub-btrfs "$WORK/grub-btrfs" >/dev/null 2>&1 \
      && sudo make -C "$WORK/grub-btrfs" install >/dev/null 2>&1 \
      && info "  + grub-btrfs built+installed" || warn "  grub-btrfs build failed"
  else
    info "  = grub-btrfs present"
  fi
  if command -v grub-btrfsd >/dev/null 2>&1; then
    # Fedora path overrides (later definitions win)
    sudo tee -a /etc/default/grub-btrfs/config >/dev/null <<'GB_CONF'
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"
GRUB_BTRFS_MKCONFIG="/usr/bin/grub2-mkconfig"
GRUB_BTRFS_SCRIPT_CHECK="grub2-script-check"
GRUB_BTRFS_MKCONFIG_LIB="/usr/share/grub/grub-mkconfig_lib"
GB_CONF
    if [ -d /home/.snapshots ]; then
      sudo mkdir -p /etc/systemd/system/grub-btrfsd.service.d
      sudo tee /etc/systemd/system/grub-btrfsd.service.d/dirs.conf >/dev/null <<'GB_SVC'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots /home/.snapshots
GB_SVC
    fi
    systemctl daemon-reload
    systemctl enable --now grub-btrfsd 2>/dev/null || true
    info "  + grub-btrfsd watching /.snapshots + /home/.snapshots"
  fi

  # ---- material GRUB theme + wolf background ------------------------------------
  sudo dnf install -y git ImageMagick >/dev/null 2>&1 || true
  if [ ! -f /boot/grub2/themes/tela/theme.txt ]; then
    git clone --depth 1 https://github.com/vinceliuice/grub2-themes "$WORK/grub2-themes" >/dev/null 2>&1
    ( cd "$WORK/grub2-themes" && sudo ./install.sh -t tela -i white -s 1080p -c 1280x720 -b >/dev/null 2>&1 ) \
      && info "  + tela GRUB theme" || warn "  GRUB theme install failed"
  else
    info "  = tela GRUB theme"
  fi
  GRUB_BG_SRC="$ASSET_GRUB_WOLF"
  [ -f "$GRUB_BG_SRC" ] || GRUB_BG_SRC="$ASSET_WOLF"
  if [ -f "$GRUB_BG_SRC" ] && [ -f /boot/grub2/themes/tela/background.jpg ]; then
    sudo convert "$GRUB_BG_SRC" -resize "1920x1080^" -gravity center -extent 1920x1080 -colorspace sRGB -strip -interlace none /tmp/etf-grub-bg.jpg 2>/dev/null \
      && sudo cp /tmp/etf-grub-bg.jpg /boot/grub2/themes/tela/background.jpg \
      && info "  + GRUB background ($(basename "$GRUB_BG_SRC"))" || warn "  GRUB background conversion failed"
    rm -f /tmp/etf-grub-bg.jpg
  fi

  # ---- /etc/default/grub + guaranteed-visible menu -------------------------------
  sudo tee /etc/default/grub >/dev/null <<'DEFAULT_GRUB'
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_GFXMODE="1920x1080,1280x720,auto"
GRUB_GFXPAYLOAD_LINUX="keep"
GRUB_CMDLINE_LINUX="rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
GRUB_FONT=/boot/grub2/fonts/unicode.pf2
GRUB_THEME="/boot/grub2/themes/tela/theme.txt"
DEFAULT_GRUB

  # kill the auto-hide flag that suppresses the menu after a successful boot
  sudo grub2-editenv /boot/grub2/grubenv unset menu_auto_hide 2>/dev/null || true
  sudo grub2-editenv /boot/grub2/grubenv unset skip_menu 2>/dev/null || true

  sudo grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 \
    && info "  + grub.cfg regenerated (menu shown every boot)" || warn "  grub2-mkconfig failed — run manually"
fi

# ==============================================================================
# 7 · Flathub apps  (productivity / dev / gaming) + dock favorites
# ==============================================================================
if [ "${DO[flatpaks]}" = 1 ]; then
  section "Flathub apps"
  have flatpak || { info "installing flatpak"; sudo dnf install -y flatpak >/dev/null 2>&1; }
  if have flatpak; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    FLATPAKS=(com.vscodium.codium io.github.shiftey.Desktop io.podman_desktop.PodmanDesktop \
              md.obsidian.Obsidian com.discordapp.Discord org.telegram.desktop \
              com.github.tchx84.Flatseal com.mattjakeman.ExtensionManager \
              com.valvesoftware.Steam net.lutris.Lutris com.heroicgameslauncher.hgl)
    for app in "${FLATPAKS[@]}"; do
      if flatpak info --user "$app" >/dev/null 2>&1; then
        info "  = $app"
      else
        flatpak install --user -y flathub "$app" >/dev/null 2>&1 && info "  + $app" || warn "  ! $app failed"
      fi
    done
    flatpak install --user -y flathub org.freedesktop.Platform.VulkanLayer.MangoHud//26.08 >/dev/null 2>&1 || \
      flatpak install --user -y flathub org.freedesktop.Platform.VulkanLayer.MangoHud >/dev/null 2>&1 || true
    flatpak install --user -y flathub org.freedesktop.Platform.VulkanLayer.gamescope//26.08 >/dev/null 2>&1 || \
      flatpak install --user -y flathub org.freedesktop.Platform.VulkanLayer.gamescope >/dev/null 2>&1 || true
  else
    warn "  flatpak unavailable"  
  fi
fi

# ---- dock favorites ----------------------------------------------------------
gsettings set org.gnome.shell favorite-apps \
  "['kitty.desktop', 'org.mozilla.firefox.desktop', 'org.gnome.Nautilus.desktop', 'com.vscodium.codium.desktop', 'md.obsidian.Obsidian.desktop', 'com.valvesoftware.Steam.desktop', 'com.heroicgameslauncher.hgl.desktop', 'com.discordapp.Discord.desktop', 'org.telegram.desktop.desktop']" 2>/dev/null || \
gsettings set org.gnome.shell favorite-apps \
  "['kitty.desktop', 'org.mozilla.firefox.desktop', 'org.gnome.Nautilus.desktop']"

# ==============================================================================
# 8 · Wrap-up
# ==============================================================================
section "done"
info "unixporn·material · eternal-fedora installed."
echo
echo "  Next steps:"
echo "    1. Log out and back in (GNOME extensions/themes activate)."
echo "    2. Open a new kitty tab — fastfetch will show the wolf."
echo "    3. Reboot once — the material GRUB menu (with Snapshot submenu) is now"
echo "       forced visible every time."
echo "    4. Commands added: sysupdate · sysfix · sysclean · syssnap · sysrollback"
echo "       · sysupgrade-major · backup-dots · fetch/ff"
echo "    5. Backups land in ~/Backups/dotfiles/ (and the project folder)."
echo
info "Re-run ./install.sh any time — it is fully idempotent."
