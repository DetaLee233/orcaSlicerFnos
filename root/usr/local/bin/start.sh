#!/bin/bash
set -euo pipefail

export HOME="${HOME:-/root}"
export DISPLAY=":1"
WEB_PORT="${WEB_PORT:-3000}"
RESOLUTION="${RESOLUTION:-1920x1080}"
VNC_USER="${VNC_USER:-abc}"
VNC_PASSWORD="${VNC_PASSWORD:-orcaslicer}"

WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"
DRINODE="${DRINODE:-/dev/dri/renderD128}"

mkdir -p "$HOME/.vnc" "$HOME/.config/OrcaSlicer" "$HOME/.cache" "$HOME/.local/share"

# Reduce WebKitGTK (OrcaSlicer's embedded browser) memory/compositing overhead
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1

# GTK file-dialog bookmark: just /models. Anything mounted under /models is
# reachable from this single bookmark (keeps the image generic for distribution).
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
printf 'file:///models 模型\n' > "$HOME/.config/gtk-3.0/bookmarks"
cp -f "$HOME/.config/gtk-3.0/bookmarks" "$HOME/.config/gtk-4.0/bookmarks"

# Clean stale X locks from a previous run in the same container
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
mkdir -p /tmp/.X11-unix 2>/dev/null || true

# The kasmvncserver wrapper requires a user entry; the fnOS gateway injects
# these credentials upstream so the browser never sees a login prompt.
if [ ! -f "$HOME/.kasmpasswd" ]; then
  printf '%s\n%s\n' "$VNC_PASSWORD" "$VNC_PASSWORD" | kasmvncpasswd -u "$VNC_USER" -w >/dev/null 2>&1 || true
fi

# User-level KasmVNC config
cat > "$HOME/.vnc/kasmvnc.yaml" <<EOF
desktop:
  resolution:
    width: ${WIDTH}
    height: ${HEIGHT}
  allow_resize: true
  pixel_depth: 24
  gpu:
    hw3d: $([ -e "$DRINODE" ] && echo true || echo false)
    drinode: ${DRINODE}
network:
  protocol: http
  interface: 0.0.0.0
  websocket_port: ${WEB_PORT}
  ssl:
    require_ssl: false
encoding:
  max_frame_rate: 60
  video_encoding_mode:
    enter_video_encoding_mode:
      time_threshold: 2
      area_threshold: 20%
    exit_video_encoding_mode:
      time_threshold: 2
server:
  http:
    httpd_directory: /usr/share/kasmvnc/www
command_line:
  prompt: false
EOF

# Session startup: window manager + OrcaSlicer
cat > "$HOME/.vnc/xstartup" <<'XEOF'
#!/bin/bash
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
openbox-session &
exec /opt/orcaslicer/AppRun
XEOF
chmod +x "$HOME/.vnc/xstartup"

exec kasmvncserver :1 \
  -geometry "$RESOLUTION" \
  -depth 24 \
  -interface 0.0.0.0 \
  -websocketPort "$WEB_PORT" \
  -xstartup "$HOME/.vnc/xstartup" \
  -fg
