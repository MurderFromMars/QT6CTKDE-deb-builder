cat > /tmp/test-build.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# qt6ct-kde — deb builder (clean + pretty)
PKGNAME="qt6ct-kde"
VERSION="0.11"
WORKDIR="$(mktemp -d)"
STAGEDIR="$WORKDIR/pkg"
DEBIAN_DIR="$STAGEDIR/DEBIAN"
INSTALL_PREFIX="/usr"
DOWNLOADS="$HOME/Downloads"

# colors
C_RESET="\033[0m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
step() { printf "${C_BLUE}→${C_RESET} %s\n" "$1"; }
done_msg() { printf "${C_GREEN}✓${C_RESET} %s\n" "$1"; }
warn() { printf "${C_YELLOW}⚠${C_RESET} %s\n" "$1"; }

# Check for sudo/root
if [ "$EUID" -ne 0 ]; then
    warn "This script needs sudo privileges to install dependencies"
    exec sudo bash "$0" "$@"
fi

step "installing build dependencies"
apt update -qq
apt install -y build-essential cmake ninja-build qt6-base-dev qt6-tools-dev libqt6svg6-dev git

step "workspace: $WORKDIR"
mkdir -p "$STAGEDIR" "$DEBIAN_DIR"

step "cloning qt6ct-kde source"
cd "$WORKDIR"
git clone https://www.opencode.net/trialuser/qt6ct src
cd src
git checkout "tags/$VERSION" 2>/dev/null || git checkout "$VERSION" 2>/dev/null || true

step "configuring"
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX

step "building"
cmake --build build

step "staging"
DESTDIR="$STAGEDIR" cmake --install build

# updater
mkdir -p "$STAGEDIR/usr/local/bin"
cat > "$STAGEDIR/usr/local/bin/${PKGNAME}-updater" <<'UPDATER_EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO="https://www.opencode.net/trialuser/qt6ct"
VERSION="0.11"
INSTALL_PREFIX="/usr"
WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

git clone "$REPO" src
cd src
git checkout "tags/$VERSION" 2>/dev/null || git checkout "$VERSION" 2>/dev/null || true

LATEST="$(git rev-parse HEAD)"
LOCAL_HASH_FILE="/var/lib/qt6ct-kde/hash"
mkdir -p /var/lib/qt6ct-kde
CURRENT="$(cat "$LOCAL_HASH_FILE" 2>/dev/null || echo none)"

[[ "$LATEST" == "$CURRENT" ]] && { rm -rf "$WORKDIR"; exit 0; }

cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
cmake --build build
cmake --install build

echo "$LATEST" > "$LOCAL_HASH_FILE"
rm -rf "$WORKDIR"
UPDATER_EOF
chmod 755 "$STAGEDIR/usr/local/bin/${PKGNAME}-updater"

# systemd
mkdir -p "$STAGEDIR/etc/systemd/system"
cat > "$STAGEDIR/etc/systemd/system/${PKGNAME}-update.service" <<SYSTEMD_EOF
[Unit]
Description=Update qt6ct-kde from upstream repo

[Service]
Type=oneshot
ExecStart=/usr/local/bin/${PKGNAME}-updater
SYSTEMD_EOF

cat > "$STAGEDIR/etc/systemd/system/${PKGNAME}-update.timer" <<SYSTEMD_EOF
[Unit]
Description=Daily update check for qt6ct-kde

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
SYSTEMD_EOF

# control
cat > "$DEBIAN_DIR/control" <<CONTROL_EOF
Package: ${PKGNAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Unknown
Description: Qt6 Configuration Utility patched for KDE
CONTROL_EOF

step "building deb"
cd "$WORKDIR"
dpkg-deb --build pkg

mkdir -p "$DOWNLOADS"
# Get original user's home if running as sudo
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
    DOWNLOADS="$REAL_HOME/Downloads"
    mkdir -p "$DOWNLOADS"
    chown "$REAL_USER:$REAL_USER" "$DOWNLOADS"
fi

mv pkg.deb "$DOWNLOADS/${PKGNAME}_${VERSION}_amd64.deb"
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER:$SUDO_USER" "$DOWNLOADS/${PKGNAME}_${VERSION}_amd64.deb"

step "cleanup"
rm -rf "$WORKDIR"

done_msg "done → $DOWNLOADS/${PKGNAME}_${VERSION}_amd64.deb"
EOF

chmod +x /tmp/test-build.sh
/tmp/test-build.sh
