
#!/data/data/com.termux/files/usr/bin/bash

set -e

DISTRO="ubuntu"
PORT=8000
OPENCODE_PASSWORD="12345"

echo "======================================"
echo "    Ubuntu + OpenCode Web Installer"
echo "======================================"

# 1. Update Termux
echo "[1/8] Updating Termux..."

pkg update -y
pkg upgrade -y
pkg install -y proot-distro curl wget git

# 2. Setup Android storage
echo "[2/8] Requesting Android storage permission..."

termux-setup-storage

echo "Storage setup command completed."

if [ -d "$HOME/storage/shared" ]; then
    echo "Android storage access confirmed."
else
    echo "WARNING: Android shared storage is unavailable."
fi

# 3. Install Ubuntu
echo "[3/8] Checking Ubuntu..."

if proot-distro login "$DISTRO" -- true >/dev/null 2>&1; then
    echo "Ubuntu already installed."
else
    proot-distro install "$DISTRO"
fi

# 4. Install OpenCode v2
echo "[4/8] Installing OpenCode..."

proot-distro login "$DISTRO" -- bash -c '
set -e

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git ca-certificates

curl -fsSL https://opencode.ai/v2/install | bash

export PATH="/root/.opencode/bin:/root/.local/bin:$PATH"

command -v opencode >/dev/null 2>&1 || {
    echo "ERROR: OpenCode installation failed."
    exit 1
}

opencode --version
'

# 5. Create start script
echo "[5/8] Creating opencode.sh..."

cat > "$HOME/opencode.sh" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash

DISTRO="ubuntu"
PORT=8000
OPENCODE_PASSWORD="12345"

echo "Checking OpenCode Web..."

# Check whether OpenCode is already running
if curl -sS -o /dev/null --max-time 2 \
    "http://127.0.0.1:$PORT/"; then

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
        echo "Android shared storage attached."
    else
        echo "Android shared storage unavailable."
    fi

    proot-distro login "${BIND_ARGS[@]}" "$DISTRO" -- bash -lc '
        export PATH="/root/.opencode/bin:/root/.local/bin:$PATH"

        cd /root/termux_home

        export OPENCODE_PASSWORD="12345"

        exec opencode serve \
            --hostname 127.0.0.1 \
            --port 8000
    ' </dev/null >/dev/null 2>&1 &

    echo "Waiting for OpenCode Web..."

    READY=0

    for i in $(seq 1 30); do
        if curl -sS -o /dev/null --max-time 1 \
            "http://127.0.0.1:$PORT/"; then
            READY=1
            break
        fi

        sleep 1
    done

    if [ "$READY" -eq 1 ]; then
        echo "OpenCode Web started successfully."
    else
        echo "WARNING: OpenCode Web did not respond."
        echo "Check Ubuntu and OpenCode installation."
    fi
fi

echo ""
echo "======================================"
echo "        OPENCODE WEB"
echo "======================================"
echo "URL:      http://127.0.0.1:$PORT"
echo "Username: opencode"
echo "Password: $OPENCODE_PASSWORD"
echo "======================================"

LAUNCHER

chmod +x "$HOME/opencode.sh"

# 6. Create stop script
echo "[6/8] Creating stop-opencode.sh..."

cat > "$HOME/stop-opencode.sh" <<'STOP'
#!/data/data/com.termux/files/usr/bin/bash

DISTRO="ubuntu"

echo "Stopping OpenCode..."

proot-distro login "$DISTRO" -- bash -lc '
    PIDS=$(pgrep -f "[o]pencode serve.*--port 8000" || true)

    if [ -z "$PIDS" ]; then
        echo "OpenCode is not running."
        exit 0
    fi

    kill $PIDS 2>/dev/null || true

    sleep 2

    PIDS=$(pgrep -f "[o]pencode serve.*--port 8000" || true)

    if [ -n "$PIDS" ]; then
        kill -9 $PIDS 2>/dev/null || true
    fi

    echo "OpenCode stopped."
'

STOP

chmod +x "$HOME/stop-opencode.sh"

# 7. Register global commands
echo "[7/8] Registering OpenCode commands..."

mkdir -p "$HOME/bin"

# Home directory launchers
cp "$HOME/opencode.sh" "$HOME/bin/start-opencode-web"
chmod +x "$HOME/bin/start-opencode-web"

# Globally accessible Termux commands
cp "$HOME/opencode.sh" "$PREFIX/bin/start-opencode"
cp "$HOME/stop-opencode.sh" "$PREFIX/bin/stop-opencode"

chmod +x "$PREFIX/bin/start-opencode"
chmod +x "$PREFIX/bin/stop-opencode"

echo "Commands registered:"
echo "  start-opencode"
echo "  stop-opencode"

# 8. Configure automatic startup
echo "[8/8] Configuring automatic startup..."

BASHRC="$HOME/.bashrc"

touch "$BASHRC"

# Remove previous installer startup block
if grep -q "# OPENCODE_WEB_AUTOSTART" "$BASHRC"; then
    sed -i \
        '/# OPENCODE_WEB_AUTOSTART/,/# END_OPENCODE_WEB_AUTOSTART/d' \
        "$BASHRC"
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
echo ""
echo "OpenCode Web: http://127.0.0.1:8000"
echo "Username:     opencode"
echo "Password:     $OPENCODE_PASSWORD"
echo ""
echo "Available commands:"
echo "  start-opencode"
echo "  stop-opencode"
echo ""
echo "======================================"
