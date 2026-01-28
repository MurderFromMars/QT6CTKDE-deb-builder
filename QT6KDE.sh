#!/usr/bin/env bash
set -euo pipefail
# qt6ct-kde — deb builder (clean + pretty)
PKGNAME="qt6ct-kde"
VERSION="0.11"
REPO_URL="https://download.qt.io/official_releases/qt6ct/qt6ct-0.9.tar.xz"  # actual source
WORKDIR="$(mktemp -d)"
STAGEDIR="$WORKDIR/pkg"
DEBIAN_DIR="$STAGEDIR/DEBIAN"
INSTALL_PREFIX="/usr"
DOWNLOADS="$HOME/Downloads"

# colors
C_RESET="\033[0m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
step() { printf "${C_BLUE}→${C_RESET} %s\n" "$1"; }
done_msg() { printf "${C_GREEN}✓${C_RESET} %s\n" "$1"; }

step "workspace: $WORKDIR"
mkdir -p "$STAGEDIR" "$DEBIAN_DIR"

step "downloading source"
cd "$WORKDIR"
# Clone the AUR repo to get the PKGBUILD
git clone "https://aur.archlinux.org/qt6ct-kde.git" aur
cd aur

# Extract source URL from PKGBUILD
SOURCE_URL=$(grep -Po '(?<=source=\()[^)]+' PKGBUILD | tr -d '"' | head -1)
step "source URL: $SOURCE_URL"

# Download and extract
wget -q "$SOURCE_URL"
tar xf *.tar.xz
cd qt6ct-*/

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
cat > "$STAGEDIR/usr/local/bin/${PKGNAME}-updater" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
AUR_REPO="https://aur.archlinux.org/qt6ct-kde.git"
INSTALL_PREFIX="/usr"
WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

git clone "$AUR_REPO" aur
cd aur

LATEST="$(git rev-parse HEAD)"
LOCAL_HASH_FILE="/var/lib/qt6ct-kde/hash"
mkdir -p /var/lib/qt6ct-kde
CURRENT="$(cat "$LOCAL_HASH_FILE" 2>/dev/null || echo none)"

[[ "$LATEST" == "$CURRENT" ]] && { rm -rf "$WORKDIR"; exit 0; }

SOURCE_URL=$(grep -Po '(?<=source=\()[^)]+' PKGBUILD | tr -d '"' | head -1)
wget -q "$SOURCE_URL"
tar xf *.tar.xz
cd qt6ct-*/

cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
cmake --build build
cmake --install build

echo "$LATEST" > "$LOCAL_HASH_FILE"
rm -rf "$WORKDIR"
EOF
chmod 755 "$STAGEDIR/usr/local/bin/${PKGNAME}-updater"

# systemd
mkdir -p "$STAGEDIR/etc/systemd/system"
cat > "$STAGEDIR/etc/systemd/system/${PKGNAME}-update.service" <<EOF
[Unit]
Description=Update qt6ct-kde from upstream repo

[Service]
Type=oneshot
ExecStart=/usr/local/bin/${PKGNAME}-updater
EOF

cat > "$STAGEDIR/etc/systemd/system/${PKGNAME}-update.timer" <<EOF
[Unit]
Description=Daily update check for qt6ct-kde

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# control
cat > "$DEBIAN_DIR/control" <<EOF
Package: ${PKGNAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Unknown
Description: Qt6 Configuration Utility patched for KDE
EOF

step "building deb"
cd "$WORKDIR"
dpkg-deb --build pkg

mkdir -p "$DOWNLOADS"
mv pkg.deb "$DOWNLOADS/${PKGNAME}_${VERSION}_amd64.deb"

step "cleanup"
rm -rf "$WORKDIR"

done_msg "done → $DOWNLOADS/${PKGNAME}_${VERSION}_amd64.deb"
