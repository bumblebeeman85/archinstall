#!/usr/bin/env bash
set -euo pipefail

# Als Normaluser mit sudo ausführen: sudo ./setup_arch_kde.sh

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als normaler Benutzer mit sudo ausführen."
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
  xdg-user-dirs git \
  open-vm-tools \
  papirus-icon-theme kde-gtk-config

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
# zusätzlicher Symlink für alternativen Suchpfad
ln -sf "/home/$TARGET_USER/.config/fastfetch/config.jsonc" "/home/$TARGET_USER/.config/fastfetch.jsonc"
chown -h "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/fastfetch.jsonc"
chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/fastfetch"

echo "==> Kitty Catppuccin (Mocha) Theme setzen ..."
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.config/kitty"
if [[ ! -f "/home/$TARGET_USER/.config/kitty/kitty.conf" ]] || ! grep -q '^include[[:space:]]\+theme.conf' "/home/$TARGET_USER/.config/kitty/kitty.conf"; then
  echo "include theme.conf" >> "/home/$TARGET_USER/.config/kitty/kitty.conf"
fi
if command -v kitty >/dev/null 2>&1; then
  sudo -u "$TARGET_USER" kitty +kitten themes --dump-theme "Catppuccin-Mocha" > "/home/$TARGET_USER/.config/kitty/theme.conf" || true
fi
chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/kitty"

echo "==> Catppuccin KDE (Farbschemata) optional bereitstellen ..."
# Catppuccin KDE Farbschemata in den Benutzer-Scope installieren (optional)
sudo -u "$TARGET_USER" bash -lc '
  set -e
  tmpdir="$(mktemp -d)"
  git clone --depth=1 https://github.com/catppuccin/kde "$tmpdir/catppuccin-kde"
  install -d -m 0755 "$HOME/.local/share/color-schemes"
  # Kopiere alle *.colors, falls vorhanden
  find "$tmpdir/catppuccin-kde" -type f -name "*.colors" -exec install -m 0644 "{}" "$HOME/.local/share/color-schemes/" \; || true
  rm -rf "$tmpdir"
' || true

echo "==> Autostart für Theme-Anwendung beim ersten Plasma-Login erstellen ..."
# Skript, das beim ersten Plasma-Login Farben, L&F und Icons setzt und sich dann selbst entfernt
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.local/bin"
cat > "/home/$TARGET_USER/.local/bin/apply-kde-themes.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

# Farben: Catppuccin Mocha, falls installiert; sonst Breeze Dark
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
  if plasma-apply-colorscheme -l | grep -q "Catppuccin.*Mocha"; then
    plasma-apply-colorscheme "Catppuccin Mocha" || true
  else
    plasma-apply-colorscheme "Breeze Dark" || true
  fi
fi

# Global Theme (L&F): Breeze Dark anwenden
if command -v plasma-apply-lookandfeel >/dev/null 2>&1; then
  plasma-apply-lookandfeel --apply org.kde.breezedark.desktop || true
fi

# Icons: Papirus-Dark setzen (KDE liest aus kdeglobals)
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Dark || true
  # Icon-Cache neu generieren
  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental || true
  fi
fi

# Autostart-Eintrag entfernen (einmalig ausführen)
rm -f "$HOME/.config/autostart/apply-kde-themes.desktop" || true
EOS
chmod 0755 "/home/$TARGET_USER/.local/bin/apply-kde-themes.sh"
chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.local/bin/apply-kde-themes.sh"

install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.config/autostart"
cat > "/home/$TARGET_USER/.config/autostart/apply-kde-themes.desktop" <<'EOD'
[Desktop Entry]
Type=Application
Exec=/home/%u/.local/bin/apply-kde-themes.sh
Icon=palette
Name=Apply KDE Themes (one-time)
Comment=Apply colors, global theme, and icons on first Plasma login
X-KDE-AutostartScript=true
OnlyShowIn=KDE;
EOD
# %u ersetzen
sed -i "s|%u|$TARGET_USER|g" "/home/$TARGET_USER/.config/autostart/apply-kde-themes.desktop"
chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.config/autostart/apply-kde-themes.desktop"

echo "==> Fertig. Nach dem ersten Plasma-Login werden Farbschema, Global Theme und Icons automatisch angewendet."
