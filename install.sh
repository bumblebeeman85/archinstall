#!/usr/bin/env bash
set -euo pipefail

# Bitte als Normaluser mit sudo ausführen: sudo ./setup_arch_kde.sh

if [[ $EUID -ne 0 ]]; then
  echo "Bitte mit sudo als normaler Benutzer ausführen."
  exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  echo "SUDO_USER ist leer oder root. Skript als normaler Benutzer mit sudo starten."
  exit 1
fi

export SYSTEMD_PAGER=cat

echo "==> System aktualisieren und Pakete installieren ..."
pacman -Syu --noconfirm
pacman -S --noconfirm --needed \
  plasma-meta sddm \
  kitty fish starship fastfetch \
  xdg-user-dirs \
  open-vm-tools

echo "==> Benutzer-Verzeichnisse initialisieren ..."
sudo -u "$TARGET_USER" xdg-user-dirs-update

echo "==> SDDM aktivieren und grafisches Target setzen ..."
systemctl enable --now sddm.service
systemctl set-default graphical.target

echo "==> open-vm-tools aktivieren ..."
systemctl enable --now vmtoolsd.service
systemctl enable --now vmware-vmblock-fuse.service

echo "==> fish als Login-Shell setzen ..."
FISH_BIN="$(command -v fish)"
if ! grep -qx "$FISH_BIN" /etc/shells; then
  echo "$FISH_BIN" >> /etc/shells
fi
chsh -s "$FISH_BIN" "$TARGET_USER"

echo "==> fish-Konfiguration (Starship + Fastfetch Autoload) schreiben ..."
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.config/fish"
cat > "/home/$TARGET_USER/.config/fish/config.fish" <<'EOF'
if status is-interactive
    if type -q starship
        starship init fish | source
    end
    if type -q fastfetch
        fastfetch
    end
end
EOF
chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/fish/config.fish"

echo "==> Fastfetch-Konfiguration bereitstellen ..."
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.config/fastfetch"
cat > "/home/$TARGET_USER/.config/fastfetch/config.jsonc" <<'JSON'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": { "type": "auto" },
  "modules": [
    "break",
    { "type": "custom", "format": "\u001b[90m┌──────────────────────Hardware──────────────────────┐" },
    { "type": "host", "key": " PC", "keyColor": "green" },
    { "type": "cpu", "key": "│ ├", "keyColor": "green" },
    { "type": "cpuusage", "key": "│ ├󰔚 Load", "keyColor": "green",
      "percent": { "type": 3, "green": 30, "yellow": 70 }, "separate": false },
    { "type": "gpu", "key": "│ ├󰍛", "keyColor": "green" },
    { "type": "memory", "key": "│ ├󰍛 RAM", "keyColor": "green",
      "percent": { "type": 3, "green": 30, "yellow": 70 } },
    { "type": "disk", "key": "└ └", "keyColor": "green",
      "percent": { "type": 3, "green": 50, "yellow": 80 } },
    { "type": "custom", "format": "\u001b[90m└────────────────────────────────────────────────────┘" },
    "break",
    { "type": "custom", "format": "\u001b[90m┌──────────────────────Software──────────────────────┐" },
    { "type": "os", "key": " OS", "keyColor": "yellow" },
    { "type": "kernel", "key": "│ ├", "keyColor": "yellow" },
    { "type": "bios", "key": "│ └", "keyColor": "yellow" },
    "break",
    { "type": "custom", "format": "\u001b[90m└────────────────────────────────────────────────────┘" },
    "break",
    { "type": "custom", "format": "\u001b[90m┌────────────────────Uptime / DT─────────────────────┐" },
    { "type": "uptime", "key": "  Uptime ", "keyColor": "magenta" },
    { "type": "datetime", "key": "  DateTime ", "keyColor": "magenta" },
    { "type": "custom", "format": "\u001b[90m└────────────────────────────────────────────────────┘" },
    { "type": "colors", "paddingLeft": 2, "symbol": "circle" }
  ]
}
JSON
# Optionaler Symlink für alternativen Suchpfad
ln -sf "/home/$TARGET_USER/.config/fastfetch/config.jsonc" "/home/$TARGET_USER/.config/fastfetch.jsonc"
chown -h "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/fastfetch.jsonc"
chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/fastfetch"

echo "==> Kitty Catppuccin (Mocha) Theme setzen ..."
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.config/kitty"
# include-Zeile einmalig sicherstellen
if [[ ! -f "/home/$TARGET_USER/.config/kitty/kitty.conf" ]] || ! grep -q '^include[[:space:]]\+theme.conf' "/home/$TARGET_USER/.config/kitty/kitty.conf"; then
  echo "include theme.conf" >> "/home/$TARGET_USER/.config/kitty/kitty.conf"
fi
# Theme-Datei per kitten themes dumpen (als Zieluser)
if command -v kitty >/dev/null 2>&1; then
  sudo -u "$TARGET_USER" kitty +kitten themes --dump-theme "Catppuccin-Mocha" > "/home/$TARGET_USER/.config/kitty/theme.conf" || true
fi
chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/kitty"

echo "==> Fertig. Neustart empfohlen."
