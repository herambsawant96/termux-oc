#!/data/data/com.termux/files/usr/bin/bash

set -e

DISTRO="ubuntu"
PORT=8000

echo "======================================"
echo "    Ubuntu + OpenCode Web Installer"
echo "======================================"

# 1. Update Termux
echo "[1/7] Updating Termux..."

pkg update -y
pkg upgrade -y
pkg install -y proot-distro curl wget git

# 2. Setup Android storage
echo "[2/7] Setting up Android storage..."

termux-setup-storage || true

if [ ! -d "$HOME/storage/shared" ]; then
    echo "WARNING: Android storage permission not granted."
fi

# 3. Install Ubuntu
echo "[3/7] Checking Ubuntu..."

if proot-distro login "$DISTRO" -- true >/dev/null 2>&1; then
    echo "Ubuntu already installed."
else
    proot-distro install "$DISTRO"
fi

# 4. Install/update OpenCode
echo "[4/7] Installing OpenCode..."

proot-distro login "$DISTRO" -- bash -c '
set -e

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git ca-certificates

curl -fsSL https://opencode.ai/install | bash

export PATH="/root/.opencode/bin:/root/.local/bin:$PATH"

command -v opencode >/dev/null 2>&1 || {
    echo "ERROR: OpenCode installation failed."
    exit 1
}

opencode --version
'

# 5. Create standalone recovery launcher
echo "[5/7] Creating opencode.sh..."

cat > "$HOME/opencode.sh" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash

PORT=8000

echo "Checking OpenCode Web..."

if curl -fsS -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/"; then
    echo "OpenCode Web is already running."
else
    echo "Starting OpenCode Web..."

    BIND_ARGS=(
        --bind "$HOME:/root/termux_home"
    )

    if [ -d "$HOME/storage/shared" ]; then
        BIND_ARGS+=(
            --bind "$HOME/storage/shared:/root/sdcard"
        )
    fi

    proot-distro login "${BIND_ARGS[@]}" ubuntu -- bash -lc '
        export PATH="/root/.opencode/bin:/root/.local/bin:$PATH"
        cd /root/termux_home
        exec opencode web --port 8000
    ' </dev/null >/dev/null 2>&1 &
fi

echo ""
echo "OpenCode Web: http://127.0.0.1:$PORT"
echo ""
LAUNCHER

chmod +x "$HOME/opencode.sh"

# 6. Create regular startup launcher
echo "[6/7] Creating automatic launcher..."

mkdir -p "$HOME/bin"
cp "$HOME/opencode.sh" "$HOME/bin/start-opencode-web"
chmod +x "$HOME/bin/start-opencode-web"

# 7. Configure Termux autostart
echo "[7/7] Configuring automatic startup..."

BASHRC="$HOME/.bashrc"
touch "$BASHRC"

if grep -q "# OPENCODE_WEB_AUTOSTART" "$BASHRC"; then
    sed -i '/# OPENCODE_WEB_AUTOSTART/,/# END_OPENCODE_WEB_AUTOSTART/d' "$BASHRC"
fi

cat >> "$BASHRC" <<'STARTUP'

# OPENCODE_WEB_AUTOSTART
if [[ $- == *i* ]]; then
    "$HOME/bin/start-opencode-web"
fi
# END_OPENCODE_WEB_AUTOSTART
STARTUP

# Launch immediately
echo ""
echo "Installation complete!"
"$HOME/opencode.sh"

echo ""
echo "======================================"
echo "         SETUP COMPLETE"
echo "======================================"
echo "Web UI: http://127.0.0.1:8000"
echo "Manual launcher: ~/opencode.sh"
echo "======================================"
