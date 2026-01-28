#!/usr/bin/env bash
set -euo pipefail

# qt6ct-kde — deb builder (Fixed Version)
PKGNAME="qt6ct-kde"
VERSION="0.11"
WORKDIR="$(mktemp -d)"
STAGEDIR="$WORKDIR/pkg"
DEBIAN_DIR="$STAGEDIR/DEBIAN"
INSTALL_PREFIX="/usr"

# Colors & Symbols
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_CYAN="\033[1;36m"
C_MAGENTA="\033[1;35m"
C_RED="\033[1;31m"

ICON_ROCKET="🚀"
ICON_PACKAGE="📦"
ICON_GEAR="⚙️ "
ICON_HAMMER="🔨"
ICON_CHECK="✓"
ICON_ARROW="→"
ICON_WARN="⚠"
ICON_SPARKLE="✨"

TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)

print_header() {
    local text="$1"
    local width=$((TERM_WIDTH - 4))
    printf "\n${C_BOLD}${C_CYAN}"
    printf "╔"
    printf '═%.0s' $(seq 1 $width)
    printf "╗\n"
    printf "║ %-$((width-1))s║\n" "$text"
    printf "╚"
    printf '═%.0s' $(seq 1 $width)
    printf "╝${C_RESET}\n\n"
}

step() { printf "${C_BLUE}${C_BOLD}  ${ICON_ARROW} ${C_RESET}${C_BOLD}%s${C_RESET}\n" "$1"; }
substep() { printf "${C_DIM}     %s${C_RESET}\n" "$1"; }
done_msg() { printf "${C_GREEN}${C_BOLD}  ${ICON_CHECK} ${C_RESET}${C_GREEN}%s${C_RESET}\n" "$1"; }
warn() { printf "${C_YELLOW}${C_BOLD}  ${ICON_WARN} ${C_RESET}${C_YELLOW}%s${C_RESET}\n" "$1"; }
error() { printf "${C_RED}${C_BOLD}  ✗ ${C_RESET}${C_RED}%s${C_RESET}\n" "$1"; }

cleanup() { 
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# SUDO CHECK
# ---------------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    print_header "${ICON_PACKAGE} qt6ct-kde Package Builder"
    warn "This script must run as root."
    echo
    echo "Run it like this:"
    echo "  sudo bash $0"
    echo
    exit 1
fi

# ---------------------------------------------------------------------------

clear
print_header "${ICON_ROCKET} Building qt6ct-kde v${VERSION}"

# Dependencies
step "${ICON_GEAR} Checking dependencies"
DEPS=("build-essential" "cmake" "ninja-build" "qt6-base-dev" "qt6-base-private-dev" "qt6-tools-dev" "libqt6svg6-dev" "qml6-module-qtquick-controls" "libkf6qqc2desktopstyle-dev" "git")
MISSING=()

for dep in "${DEPS[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "install ok installed"; then
        MISSING+=("$dep")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    substep "Installing: ${MISSING[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || { error "Failed to update package lists"; exit 1; }
    apt-get install -y -qq "${MISSING[@]}" || { error "Failed to install dependencies"; exit 1; }
    done_msg "Dependencies installed"
else
    done_msg "All dependencies satisfied"
fi

echo

# Workspace
step "${ICON_PACKAGE} Preparing workspace"
mkdir -p "$STAGEDIR" "$DEBIAN_DIR" || { error "Failed to create workspace"; exit 1; }
substep "Working in: ${C_DIM}$WORKDIR${C_RESET}"
done_msg "Workspace ready"

echo

# Clone
step "${ICON_PACKAGE} Fetching source code"
cd "$WORKDIR" || exit 1

if ! git clone --quiet --depth 1 --branch "$VERSION" https://www.opencode.net/trialuser/qt6ct src 2>/dev/null; then
    substep "Trying alternative clone method..."
    if ! git clone --quiet https://www.opencode.net/trialuser/qt6ct src; then
        error "Failed to clone repository"
        exit 1
    fi
    cd src || exit 1
    git checkout "tags/$VERSION" 2>/dev/null || git checkout "$VERSION" 2>/dev/null || {
        warn "Could not checkout version $VERSION, using default branch"
    }
else
    cd src || exit 1
fi

COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
substep "Commit: ${C_CYAN}$COMMIT${C_RESET}"
done_msg "Source ready"

echo

# Configure
step "${ICON_GEAR} Configuring build"
if ! cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" > /dev/null 2>&1; then
    error "CMake configuration failed"
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
    exit 1
fi
done_msg "Configuration complete"

echo

# Build
step "${ICON_HAMMER} Compiling"
if ! cmake --build build --parallel 2>&1 | grep -i "error" > /dev/null; then
    cmake --build build --parallel > /dev/null 2>&1 || {
        error "Build failed"
        cmake --build build --parallel
        exit 1
    }
fi
done_msg "Build complete"

echo

# Stage
step "${ICON_PACKAGE} Staging files"
DESTDIR="$STAGEDIR" cmake --install build > /dev/null 2>&1 || {
    error "Installation to staging directory failed"
    exit 1
}
done_msg "Files staged"

echo

# Updater
step "${ICON_GEAR} Creating auto-updater"
mkdir -p "$STAGEDIR/usr/local/bin"
cat > "$STAGEDIR/usr/local/bin/${PKGNAME}-updater" <<'UPDATER_EOF'
#!/usr/bin/env bash
set -euo pipefail

REPO="https://www.opencode.net/trialuser/qt6ct"
VERSION="0.11"
INSTALL_PREFIX="/usr"
WORKDIR="$(mktemp -d)"

cleanup() {
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

cd "$WORKDIR" || exit 1

if ! git clone --quiet --depth 1 --branch "$VERSION" "$REPO" src 2>/dev/null; then
    git clone --quiet "$REPO" src || exit 1
    cd src || exit 1
    git checkout "tags/$VERSION" 2>/dev/null || git checkout "$VERSION" 2>/dev/null || true
else
    cd src || exit 1
fi

LATEST="$(git rev-parse HEAD)"
LOCAL_HASH_FILE="/var/lib/qt6ct-kde/hash"
mkdir -p /var/lib/qt6ct-kde
CURRENT="$(cat "$LOCAL_HASH_FILE" 2>/dev/null || echo none)"

if [ "$LATEST" = "$CURRENT" ]; then
    exit 0
fi

if ! cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" > /dev/null 2>&1; then
    exit 1
fi

if ! cmake --build build --parallel > /dev/null 2>&1; then
    exit 1
fi

if ! cmake --install build > /dev/null 2>&1; then
    exit 1
fi

echo "$LATEST" > "$LOCAL_HASH_FILE"
UPDATER_EOF

chmod 755 "$STAGEDIR/usr/local/bin/${PKGNAME}-updater"

mkdir -p "$STAGEDIR/etc/systemd/system"
cat > "$STAGEDIR/etc/systemd/system/${PKGNAME}-update.service" <<SERVICE_EOF
[Unit]
Description=Update qt6ct-kde from upstream repo

[Service]
Type=oneshot
ExecStart=/usr/local/bin/${PKGNAME}-updater
SERVICE_EOF

cat > "$STAGEDIR/etc/systemd/system/${PKGNAME}-update.timer" <<TIMER_EOF
[Unit]
Description=Daily update check for qt6ct-kde

[Timer]
OnCalendar=daily
Persistent=true
Unit=${PKGNAME}-update.service

[Install]
WantedBy=timers.target
TIMER_EOF

done_msg "Auto-updater configured"

echo

# Calculate installed size
INSTALLED_SIZE=$(du -sk "$STAGEDIR" | cut -f1)

# Control file
ARCH="$(dpkg --print-architecture)"
cat > "$DEBIAN_DIR/control" <<CONTROL_EOF
Package: ${PKGNAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: qt6ct-kde Builder <noreply@example.com>
Depends: libqt6core6, libqt6gui6, libqt6widgets6, libqt6svg6, qml-module-qtquick-controls, qml-module-org-kde-qqc2desktopstyle
Description: Qt6 Configuration Utility patched for KDE
 qt6ct is a program that allows users to configure Qt6 settings
 (theme, font, icons, etc.) under desktop environments other than KDE.
 This is a KDE-compatible patched version that can theme KDE applications
 like Dolphin outside of Plasma desktop environment.
CONTROL_EOF

# Create postinst script to set up environment
cat > "$DEBIAN_DIR/postinst" <<POSTINST_EOF
#!/bin/bash
set -e

# Set up QT_QPA_PLATFORMTHEME for all users
PROFILE_FILE="/etc/profile.d/qt6ct.sh"

cat > "\$PROFILE_FILE" <<'ENV_EOF'
# Set Qt6 platform theme to qt6ct
export QT_QPA_PLATFORMTHEME=qt6ct
ENV_EOF

chmod 644 "\$PROFILE_FILE"

echo ""
echo "========================================="
echo "qt6ct-kde installation complete!"
echo "========================================="
echo ""
echo "IMPORTANT: To activate qt6ct, you need to either:"
echo "  1. Log out and log back in, OR"
echo "  2. Run: source /etc/profile.d/qt6ct.sh"
echo ""
echo "Then you can configure Qt6 apps by running: qt6ct"
echo ""

exit 0
POSTINST_EOF

chmod 755 "$DEBIAN_DIR/postinst"

# Create prerm script to clean up
cat > "$DEBIAN_DIR/prerm" <<PRERM_EOF
#!/bin/bash
set -e

# Stop and disable the update timer if it's running
if systemctl is-active --quiet ${PKGNAME}-update.timer; then
    systemctl stop ${PKGNAME}-update.timer
fi

if systemctl is-enabled --quiet ${PKGNAME}-update.timer 2>/dev/null; then
    systemctl disable ${PKGNAME}-update.timer
fi

exit 0
PRERM_EOF

chmod 755 "$DEBIAN_DIR/prerm"

# Create postrm script to remove environment file
cat > "$DEBIAN_DIR/postrm" <<POSTRM_EOF
#!/bin/bash
set -e

if [ "\$1" = "purge" ]; then
    rm -f /etc/profile.d/qt6ct.sh
    rm -rf /var/lib/qt6ct-kde
    
    echo "qt6ct-kde has been completely removed."
    echo "You may need to log out and back in to clear the environment variable."
fi

exit 0
POSTRM_EOF

chmod 755 "$DEBIAN_DIR/postrm"

# Build package
step "${ICON_PACKAGE} Building .deb package"
cd "$WORKDIR" || exit 1

if ! dpkg-deb --build --root-owner-group pkg > /dev/null 2>&1; then
    error "Package build failed"
    dpkg-deb --build --root-owner-group pkg
    exit 1
fi

# Determine appropriate output location
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    OUTPUT_DIR="$USER_HOME/Downloads"
else
    OUTPUT_DIR="/root"
fi

# Create Downloads directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/${PKGNAME}_${VERSION}_${ARCH}.deb"
mv pkg.deb "$OUTPUT_FILE" || { error "Failed to move package"; exit 1; }
chown "${SUDO_USER:-root}:${SUDO_USER:-root}" "$OUTPUT_FILE" 2>/dev/null || true

PKG_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
done_msg "Package created (${PKG_SIZE})"

echo

print_header "${ICON_SPARKLE} Build Complete!"

printf "${C_BOLD}Package:${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$OUTPUT_FILE"
printf "${C_BOLD}Version:${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$VERSION"
printf "${C_BOLD}Size:${C_RESET}    ${C_CYAN}%s${C_RESET}\n\n" "$PKG_SIZE"

printf "${C_BOLD}To install:${C_RESET}\n"
printf "  ${C_DIM}\$${C_RESET} sudo apt install %s\n" "$OUTPUT_FILE"
printf "  ${C_DIM}\$${C_RESET} sudo systemctl enable --now ${PKGNAME}-update.timer\n\n"

printf "${C_DIM}The auto-updater will check for updates daily.${C_RESET}\n"
