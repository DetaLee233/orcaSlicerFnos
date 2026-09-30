#!/bin/bash
set -euo pipefail

APP=orcaslicer
VOL=/vol2
APPDIR=/var/apps/$APP
TARGET=$VOL/@appcenter/$APP
SRC=/vol1/orcaslicer/fpk
ICON=/tmp/opencode/orca/squashfs-root/OrcaSlicer.png

# volume-side dirs
mkdir -p "$TARGET/ui/images"
mkdir -p "$VOL/@appmeta/$APP" "$VOL/@appconf/$APP" "$VOL/@apphome/$APP" "$VOL/@apptemp/$APP" "$VOL/@appdata/$APP"

# app dir
mkdir -p "$APPDIR/cmd" "$APPDIR/config" "$APPDIR/wizard" "$APPDIR/shares"
cp -a "$SRC/cmd/." "$APPDIR/cmd/"
cp "$ICON" "$APPDIR/ICON.PNG"
cp "$ICON" "$APPDIR/ICON_256.PNG"

# symlinks like vs-code
ln -sfn "$VOL/@appconf/$APP"  "$APPDIR/etc"
ln -sfn "$VOL/@apphome/$APP"  "$APPDIR/home"
ln -sfn "$VOL/@appmeta/$APP"  "$APPDIR/meta"
ln -sfn "$VOL/@apptemp/$APP"  "$APPDIR/tmp"
ln -sfn "$VOL/@appdata/$APP"  "$APPDIR/var"
ln -sfn "$TARGET"             "$APPDIR/target"

# manifest
cat > "$APPDIR/manifest" <<'EOF'
appname="orcaslicer"
version="2.4.2"
desc="OrcaSlicer 3D 打印切片（Docker + KasmVNC，支持 GPU，从桌面直接打开）"
arch="noarch"
maintainer="OrcaSlicer"
maintainer_url="https://github.com/OrcaSlicer/OrcaSlicer"
distributor="local"
distributor_url=""
os_min_ver="0.8.1"
beta="no"
reloadui="yes"
desktop_uidir="ui"
display_name="OrcaSlicer"
desktop_appname="orcaslicer.Application"
source=thirdparty
EOF

# config
cat > "$APPDIR/config/resource" <<'EOF'
{}
EOF
cat > "$APPDIR/config/privilege" <<'EOF'
{
    "defaults": {
        "run-as": "package"
    },
    "username": "orcaslicer"
}
EOF

# target payload
cat > "$TARGET/ui/config" <<'EOF'
{
    ".url": {
        "orcaslicer.Application": {
            "title": "OrcaSlicer",
            "desc": "3D 打印切片软件",
            "icon": "images/icon_{0}.png",
            "type": "url",
            "protocol": "http",
            "port": "13000",
            "allUsers": false
        }
    }
}
EOF
cp "$ICON" "$TARGET/ui/images/icon_256.png"
cp "$ICON" "$TARGET/ui/images/icon_64.png"

echo "filesystem done"
ls -la "$APPDIR"
ls -la "$TARGET"
