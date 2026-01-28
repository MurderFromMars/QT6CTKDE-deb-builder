#!/usr/bin/env bash
set -euo pipefail

# qt6ct-kde — deb builder
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
ICON_CLEAN="🧹"
ICON_SPARKLE="✨"

TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)

print_header() {
    local text="$1"
    local width=$((TERM_WIDTH - 4))
    printf "\n${C_BOLD}${C_CYAN}"
    printf "╔"
    printf "═%.0s" $(seq 1 $width)
    printf "╗\n"
    printf "║ %-$((width-1))s║\n" "$text"
    printf "╚"
    printf "═%.0s" $(seq 1 $width)
    printf "╝${C_RESET}\n\n"
}

step() { printf "${C_BLUE}${C_BOLD}  ${ICON_ARROW} ${C_RESET}${C_BOLD}%s${C_RESET}\n" "$1"; }
substep() { printf "${C_DIM}     %s${C_RESET}\n" "$1"; }
done_msg() { printf "${C_GREEN}${C_BOLD}  ${ICON_CHECK} ${C_RESET}${C_GREEN}%s${C_RESET}\n" "$1"; }
warn() { printf "${C_YELLOW}${C_BOLD}  ${ICON_WARN} ${C_RESET}${C_YELLOW}%s${C_RESET}\n" "$1"; }

progress_bar() {
    local current=$1 total=$2 width=40
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    printf "\r  ${C_CYAN}["
    printf "${C_GREEN}█%.0s" $(seq 1 $filled)
    printf "${C_DIM}░%.0s" $(seq 1 $empty)
    printf "${C_CYAN}]${C_RESET} ${C_BOLD}%3d%%${C_RESET}" $percentage
}

spinner() {
    local pid="$1" message="$2"
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    printf "  "
    while kill -0 "$pid" 2>/dev/null; do
        printf "${C_MAGENTA}%c${C_RESET} ${C_DIM}%s${C_RESET}" "$spinstr" "$message"
        spinstr="${spinstr#?}${spinstr%${spinstr#?}}"
        sleep 0.1
        printf "\r"
    done
    wait "$pid" || true   # ← CRITICAL FIX
    printf "  ${C_GREEN}${ICON_CHECK}${C_RESET} ${C_DIM}%s${C_RESET}\n" "$message"
}

cleanup() { [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# FIXED SUDO LOGIC — SAFE FOR curl | bash
# ---------------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    print_header "${ICON_PACKAGE} qt6ct-kde Package Builder"
    warn "This script must run as root."
    echo
    echo "Run it like this:"
    echo "  curl -fsSL <url> -o QT6KDE.sh"
    echo "  chmod +x QT6KDE.sh"
    echo "  sudo ./QT6KDE.sh"
    echo
    exit 1
fi

# ---------------------------------------------------------------------------

clear
print_header "${ICON_ROCKET} Building qt6ct-kde v${VERSION}"

# Dependencies
step "${ICON_GEAR} Checking dependencies"
DEPS=("build-essential" "cmake" "ninja-build" "qt6-base-dev" "qt6-tools-dev" "libqt6svg6-dev" "git")
MISSING=()

for dep in "${DEPS[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "install ok installed"; then
        MISSING+=("$dep")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    substep "Installing: ${MISSING[*]}"
    apt update -qq 2>/dev/null || true
    total=${#MISSING[@]}
    current=0
    for dep in "${MISSING[@]}"; do
        ((current++))
        apt install -y "$dep" >/dev/null 2>&1 || true &
        spinner $! "Installing $dep ($current/$total)"
    done
    done_msg "Dependencies installed"
else
    done_msg "All dependencies satisfied"
fi

echo

# Workspace
step "${ICON_PACKAGE} Preparing workspace"
mkdir -p "$STAGEDIR" "$DEBIAN_DIR"
substep "Working in: ${C_DIM}$WORKDIR${C_RESET}"
done_msg "Workspace ready"

echo

# Clone
step "${ICON_PACKAGE} Fetching source code"
cd "$WORKDIR"
git clone https://www.opencode.net/trialuser/qt6ct src >/dev/null 2>&1 &
spinner $! "Cloning repository"
cd src
git checkout "tags/$VERSION" 2>/dev/null || git checkout "$VERSION" 2>/dev/null || true
COMMIT=$(git rev-parse --short HEAD)
substep "Commit: ${C_CYAN}$COMMIT${C_RESET}"
done_msg "Source ready"

echo

# Configure
step "${ICON_GEAR} Configuring build"
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" >/dev/null 2>&1 &
spinner $! "Running CMake"
done_msg "Configuration complete"

echo

# Build
step "${ICON_HAMMER} Compiling"
cmake --build build 2>&1 | while read -r line; do
    if [[ $line =~ 

\[([0-9]+)/([0-9]+)\]

 ]]; then
        progress_bar "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
done
printf "\n"
done_msg "Build complete"

echo

# Stage
step "${ICON_PACKAGE} Staging files"
DESTDIR="$STAGEDIR" cmake --install build >/dev/null 2>&1 &
spinner $! "Installing to staging area"
done_msg "Files staged"

echo

# Updater
step "${ICON_GEAR} Creating auto-updater"
mkdir -p "$STAGEDIR/usr/local/bin"
cat > "$STAGEDIR/usr/local/bin/${PKGNAME}-updater" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO="https://www.opencode.net/trialuser/qt6ct"
VERSION="0.11"
INSTALL_PREFIX="/usr"
WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

git clone "$REPO" src >/dev/null 2>&1
cd src
git checkout "tags/$VERSION" 2>/dev/null || git checkout "$VERSION" 2>/dev/null || true

LATEST="$(git rev-parse HEAD)"
LOCAL_HASH_FILE="/var/lib/qt6ct-kde/hash"
mkdir -p /var/lib/qt6ct-kde
CURRENT="$(cat "$LOCAL_HASH_FILE" 2>/dev/null || echo none)"

[[ "$LATEST" == "$CURRENT" ]] && { rm -rf "$WORKDIR"; exit 0; }

cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" >/dev/null 2>&1
cmake --build build >/dev/null 2>&1
cmake --install build >/dev/null 2>&1

echo "$LATEST" > "$LOCAL_HASH_FILE"
rm -rf "$WORKDIR"
EOF
chmod 755 "$STAGEDIR/usr/local/bin/${PKGNAME}-updater"

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
Unit=${PKGNAME}-update.service

[Install]
WantedBy=timers.target
EOF

done_msg "Auto-updater configured"

echo

# Control file
ARCH="$(dpkg --print-architecture)"
cat > "$DEBIAN_DIR/control" <<EOF
Package: ${PKGNAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: qt6ct-kde Builder <noreply@example>
Description: Qt6 Configuration Utility patched for KDE
EOF

# Build package
step "${ICON_PACKAGE} Building .deb package"
cd "$WORKDIR"
dpkg-deb --build pkg >/dev/null 2>&1 &
spinner $! "Creating package"

OUTPUT_FILE="/root/${PKGNAME}_${VERSION}_${ARCH}.deb"
mv pkg.deb "$OUTPUT_FILE"

PKG_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
done_msg "Package created (${PKG_SIZE})"

echo

print_header "${ICON_SPARKLE} Build Complete!"

printf "${C_BOLD}Package:${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$OUTPUT_FILE"
printf "${C_BOLD}Version:${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$VERSION"
printf "${C_BOLD}Size:${C_RESET}    ${C_CYAN}%s${C_RESET}\n\n" "$PKG_SIZE"

printf "${C_BOLD}To install:${C_RESET}\n"
printf "  ${C_DIM}\$${C_RESET} sudo dpkg -i %s\n" "$OUTPUT_FILE"
printf "  ${C_DIM}\$${C_RESET} sudo systemctl enable --now ${PKGNAME}-update.timer\n\n"

printf "${C_DIM}The auto-updater will check for updates daily.${C_RESET}\n"
