#!/usr/bin/env python3
# fnOS unified-gateway bridge for OrcaSlicer (KasmVNC).
# Binds <target>/app.sock; fnOS forwards /app/<appname>/... to it (prefix preserved).
# Strips the prefix and reverse-proxies HTTP + WebSocket to KasmVNC (127.0.0.1:<ORCA_PORT>).
import base64
import os
import signal
import socket
import socketserver
import sys
import threading

SELF = os.environ.get("TRIM_APPNAME") or "orcaslicer"
TARGET = os.environ.get("TRIM_APPDEST") or "/var/apps/orcaslicer/target"
PREFIX = "/app/" + SELF
SOCK_PATH = os.path.join(TARGET, "app.sock")
PID_PATH = os.path.join(TARGET, "gateway.pid")
UP_HOST = os.environ.get("ORCA_HOST") or "127.0.0.1"
UP_PORT = int(os.environ.get("ORCA_PORT") or 13000)
# Credentials injected upstream so the browser never sees KasmVNC's login prompt.
AUTH = os.environ.get("ORCA_AUTH") or "abc:orcaslicer"
AUTH_HDR = "Authorization: Basic " + base64.b64encode(AUTH.encode("utf-8")).decode("ascii")

HEADER_LIMIT = 256 * 1024


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


class Gateway(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        try:
            conn.settimeout(60)
        except OSError:
            pass

        buf = b""
        while b"\r\n\r\n" not in buf and len(buf) < HEADER_LIMIT:
            try:
                chunk = conn.recv(4096)
            except OSError:
                return
            if not chunk:
                return
            buf += chunk

        if b"\r\n\r\n" not in buf:
            return
        head, _, rest = buf.partition(b"\r\n\r\n")
        lines = head.split(b"\r\n")
        try:
            method, path, version = lines[0].decode("latin1").split(" ", 2)
        except ValueError:
            return

        inner = path
        if path == PREFIX or path.startswith(PREFIX + "/"):
            inner = path[len(PREFIX):] or "/"

        headers = lines[1:]
        lower = [h.decode("latin1").lower() for h in headers]
        is_ws = any(h.startswith("upgrade: websocket") for h in lower)

        out = ["%s %s %s" % (method, inner, version)]
        for h in headers:
            hl = h.decode("latin1")
            if hl.lower().startswith("authorization:"):
                continue
            out.append(hl)
        out.append(AUTH_HDR)
        if not is_ws:
            out.append("Connection: close")
        raw = ("\r\n".join(out) + "\r\n\r\n").encode("latin1") + rest

        try:
            up = socket.create_connection((UP_HOST, UP_PORT), timeout=15)
        except OSError:
            try:
                conn.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            except OSError:
                pass
            return

        try:
            up.sendall(raw)
            if not is_ws:
                try:
                    up.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
        except OSError:
            up.close()
            return

        threading.Thread(target=pump, args=(conn, up), daemon=True).start()
        try:
            while True:
                data = up.recv(65536)
                if not data:
                    break
                conn.sendall(data)
        except OSError:
            pass
        finally:
            try:
                up.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            up.close()
            try:
                conn.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


class UnixServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True
    allow_reuse_address = False


def cleanup(*_args):
    for path in (SOCK_PATH, PID_PATH):
        try:
            os.unlink(path)
        except OSError:
            pass
    raise SystemExit(0)


def main():
    try:
        if os.path.exists(SOCK_PATH):
            os.unlink(SOCK_PATH)
    except OSError:
        pass
    server = UnixServer(SOCK_PATH, Gateway)
    try:
        os.chmod(SOCK_PATH, 0o666)
    except OSError:
        pass
    try:
        with open(PID_PATH, "w") as fh:
            fh.write(str(os.getpid()))
    except OSError:
        pass
    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)
    sys.stderr.write("orcaslicer-gateway: %s -> %s:%d (prefix %s)\n" % (SOCK_PATH, UP_HOST, UP_PORT, PREFIX))
    sys.stderr.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
