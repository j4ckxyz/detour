#!/usr/bin/env bash
# Wraps the Linux export (binary with embedded .pck + rvcore .so) into an AppImage.
#
#   tools/package/appimage.sh export/linux dist/Detour-x86_64.AppImage
#
# Needs appimagetool on PATH or in $APPIMAGETOOL. Runs without FUSE (CI containers).
set -euo pipefail
src="$1"
out="$2"
root="$(cd "$(dirname "$0")/../.." && pwd)"
appdir="$(mktemp -d)/Detour.AppDir"

mkdir -p "$appdir/usr/bin" "$(dirname "$out")"
cp "$src"/detour.x86_64 "$src"/*.so "$appdir/usr/bin/"
chmod +x "$appdir/usr/bin/detour.x86_64"
cp "$root/game/icon.png" "$appdir/detour.png"

cat > "$appdir/detour.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Detour
Comment=Co-op RV road trip through procedurally generated wilderness
Exec=detour.x86_64
Icon=detour
Categories=Game;
Terminal=false
DESKTOP

cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/detour.x86_64" "$@"
APPRUN
chmod +x "$appdir/AppRun"

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGETOOL:-appimagetool}" --no-appstream "$appdir" "$out"
echo "built $out"
