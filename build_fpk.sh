#!/bin/bash
# Build a proper fnOS .fpk for OrcaSlicer
#  .fpk = tar.gz with package-root members (no top dir); manifest.checksum = md5(app.tgz)
set -euo pipefail
umask 022

ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/.fpkbuild"
ICON="$ROOT/icon.png"
APP=orcaslicer
VER=2.4.2
IMG="orcaslicer:$VER"

rm -rf "$PKG"
mkdir -p "$PKG/outer/payload/app" "$PKG/outer/payload/ui/images" "$PKG/outer/payload/config"
mkdir -p "$PKG/outer/cmd" "$PKG/outer/config" "$PKG/outer/ui/images" "$PKG/outer/wizard"

# ---------------- payload (becomes target/ after install) ----------------
cp "$ICON" "$PKG/outer/payload/ui/images/icon_256.png"
cp "$ICON" "$PKG/outer/payload/ui/images/icon_64.png"
cat > "$PKG/outer/payload/ui/config" <<'EOF'
{
    ".url": {
        "orcaslicer.Application": {
            "title": "OrcaSlicer",
            "desc": "3D 打印切片软件",
            "icon": "images/icon_{0}.png",
            "type": "iframe",
            "protocol": "",
            "gatewayPrefix": "/app/orcaslicer",
            "gatewaySocket": "app.sock",
            "url": "/app/orcaslicer/vnc.html?path=app/orcaslicer/websockify&autoconnect=1&resize=remote",
            "allUsers": true
        }
    }
}
EOF
cp "$ROOT/gateway.py" "$PKG/outer/payload/gateway.py"
cat > "$PKG/outer/payload/app/docker-compose.yaml" <<'EOF'
services:
  orcaslicer:
    image: "orcaslicer:2.4.2"
    container_name: orcaslicer
    devices:
      - /dev/dri:/dev/dri
    volumes:
      - /var/apps/orcaslicer/shares/config:/root/.config
      - /var/apps/orcaslicer/shares/cache:/root/.cache
      - /var/apps/orcaslicer/shares/models:/models
    network_mode: bridge
    ports:
      - "13000:3000"
    restart: unless-stopped
    environment:
      - TZ=Asia/Shanghai
      - VNC_USER=abc
      - VNC_PASSWORD=orcaslicer
      - RESOLUTION=1920x1080
EOF
cat > "$PKG/outer/payload/config/privilege" <<'EOF'
{
    "defaults": {
        "run-as": "root"
    }
}
EOF
cat > "$PKG/outer/payload/config/resource" <<'EOF'
{}
EOF

echo ">>> docker save $IMG (this is the big step)"
docker save "$IMG" -o "$PKG/outer/payload/image.tar"
ls -lh "$PKG/outer/payload/image.tar"
chmod 644 "$PKG/outer/payload/image.tar"
chmod -R u+rwX,go+rX,go-w "$PKG/outer/payload"

# app.tgz = payload, members at root
echo ">>> packing app.tgz"
tar -czf "$PKG/outer/app.tgz" -C "$PKG/outer/payload" .
CHECKSUM=$(md5sum "$PKG/outer/app.tgz" | awk '{print $1}')
echo ">>> checksum(app.tgz) = $CHECKSUM"

# ---------------- package root metadata ----------------
cp "$ICON" "$PKG/outer/ICON.PNG"
cp "$ICON" "$PKG/outer/ICON_256.PNG"
cp "$ICON" "$PKG/outer/ui/images/icon_256.png"
cp "$ICON" "$PKG/outer/ui/images/icon_64.png"
cp "$PKG/outer/payload/ui/config" "$PKG/outer/ui/config"
cp "$PKG/outer/payload/config/privilege" "$PKG/outer/config/privilege"
cp "$PKG/outer/payload/config/resource"  "$PKG/outer/config/resource"

cat > "$PKG/outer/manifest" <<EOF
appname               = $APP
version               = $VER
display_name          = OrcaSlicer
desc                  = OrcaSlicer 开源 3D 打印切片软件，Docker + KasmVNC 方式运行，支持 AMD/Intel 核显硬件加速。安装后从飞牛桌面点击图标即可打开；首次登录：用户名 abc，密码 orcaslicer。
platform              = all
source                = thirdparty
maintainer            = OrcaSlicer
distributor           = local
maintainer_url        = https://github.com/OrcaSlicer/OrcaSlicer
os_min_version        = 1.1.3100
service_port          = 13000
checkport             = true
ctl_stop              = true
desktop_uidir         = ui
desktop_applaunchname = orcaslicer.Application
changelog             = v2.4.2 基于 Ubuntu 24.04 + KasmVNC 1.5.0 打包，内置软件镜像，支持 /dev/dri 硬件加速。
checksum              = $CHECKSUM
EOF

# ---------------- cmd lifecycle scripts ----------------
cat > "$PKG/outer/cmd/install_init" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$PKG/outer/cmd/install_callback" <<'EOF'
#!/bin/bash
set -u
TARGET="${TRIM_APPDEST:-/var/apps/${TRIM_APPNAME}/target}"
LOG="${TRIM_TEMP_LOGFILE:-/dev/null}"
mkdir -p /var/apps/orcaslicer/shares/config /var/apps/orcaslicer/shares/cache /var/apps/orcaslicer/shares/models 2>/dev/null
if [ -f "$TARGET/image.tar" ]; then
  docker load -i "$TARGET/image.tar" >>"$LOG" 2>&1 || true
fi
exit 0
EOF
cat > "$PKG/outer/cmd/upgrade_init" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$PKG/outer/cmd/upgrade_callback" <<'EOF'
#!/bin/bash
set -u
TARGET="${TRIM_APPDEST:-/var/apps/${TRIM_APPNAME}/target}"
LOG="${TRIM_TEMP_LOGFILE:-/dev/null}"
[ -f "$TARGET/image.tar" ] && docker load -i "$TARGET/image.tar" >>"$LOG" 2>&1 || true
exit 0
EOF
cat > "$PKG/outer/cmd/uninstall_init" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$PKG/outer/cmd/uninstall_callback" <<'EOF'
#!/bin/bash
TARGET="${TRIM_APPDEST:-/var/apps/orcaslicer/target}"
[ -f "$TARGET/gateway.pid" ] && kill "$(cat "$TARGET/gateway.pid" 2>/dev/null)" 2>/dev/null
rm -f "$TARGET/gateway.pid" "$TARGET/app.sock"
docker rm -f orcaslicer >/dev/null 2>&1 || true
exit 0
EOF
cat > "$PKG/outer/cmd/config_init" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$PKG/outer/cmd/config_callback" <<'EOF'
#!/bin/bash
exit 0
EOF
cp "$ROOT/cmd-main" "$PKG/outer/cmd/main"
chmod +x "$PKG/outer/cmd/"*

# ---------------- normalise permissions (shell umask may be restrictive) ----
chmod 644 "$PKG/outer/payload/image.tar"
chmod -R u+rwX,go+rX,go-w "$PKG/outer/payload" "$PKG/outer/config" "$PKG/outer/ui" "$PKG/outer/wizard"
chmod 755 "$PKG/outer/cmd/"*
chmod 644 "$PKG/outer/manifest" "$PKG/outer/app.tgz" "$PKG/outer/ICON.PNG" "$PKG/outer/ICON_256.PNG"

# ---------------- assemble outer fpk ----------------
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/orcaslicer_${VER}_all.fpk"
rm -f "$OUT"
echo ">>> assembling $OUT"
tar -czf "$OUT" -C "$PKG/outer" manifest app.tgz cmd config ui wizard ICON.PNG ICON_256.PNG
ls -lh "$OUT"
echo ">>> outer members:"
tar tzf "$OUT"
