# orcaSlicerFnos

把 **OrcaSlicer** 打包成飞牛 fnOS（基于 Debian 12）的应用，运行方式参考飞牛官方
Chrome 浏览器（KasmVNC + 统一网关），可从 **飞牛 Web 桌面内嵌打开**、无登录、分辨率随窗口自适应。

---

## 目录结构

```
orcaSlicerFnos/
├── AGENTS.md                 # 本文档
├── Dockerfile                # 镜像：ubuntu:24.04 + KasmVNC + OrcaSlicer
├── .dockerignore
├── root/
│   └── usr/local/bin/start.sh# 容器入口：拉起 KasmVNC(:3000) + openbox + OrcaSlicer
├── gateway.py                # 宿主机网关：绑定 target/app.sock，反代 HTTP/WS 到 KasmVNC
├── cmd-main                  # fnOS 应用生命周期脚本（start/stop/status：容器 + 网关）
├── build_fpk.sh              # 打 .fpk 包（内置镜像，产物在 dist/）
├── docker-compose.yml        # 本地开发/调试用（映射 13000:3000，挂载 ./data、./models）
├── icon.png                  # 应用图标（OrcaSlicer.png）
├── kasmvnc_noble.deb         # KasmVNC 1.5.0 Ubuntu Noble 版（构建镜像用）
├── Orca.AppImage             # OrcaSlicer v2.4.2 Linux AppImage（Ubuntu 24.04 构建）
├── dist/                     # 构建产物：orcaslicer_<ver>_all.fpk
├── data/  models/            # 本地调试用的持久化目录
└── .fpkbuild/                # build_fpk.sh 的临时目录（可删）
```

---

## 关键设计

### 1. 为什么底包是 ubuntu:24.04
OrcaSlicer 的官方 AppImage 是 **Ubuntu 24.04 构建**，要求 `GLIBC_2.38`；
fnOS 本体是 Debian 12（glibc 2.36），**跑不起来**。所以用 `ubuntu:24.04` 做容器底包。

### 2. 显示与串流
- **KasmVNC 1.5.0**（Ubuntu Noble 版 deb）：X server + VNC + HTML5 客户端三合一，监听容器内 `:3000`。
- Chromium 那套用的是 LinuxServer.io 的 KasmVNC baseimage（bookworm），glibc 不够，所以这里自己装 KasmVNC。
- `desktop.gpu.hw3d: true` + `--device /dev/dri`：AMD/Intel 核显硬件加速。
- openbox 跑在 KasmVNC 的 X 会话里；`xstartup` 里启动 openbox 并 `exec` OrcaSlicer。

### 3. 内嵌到飞牛 Web 桌面（统一网关）
飞牛桌面只对内嵌 `app_service.type = iframe` 的应用用 `<iframe>` 打开（`type=url` 会 `window.open`）。
统一网关约定：**应用在自身目录创建 `target/app.sock`，飞牛把 `/app/<appname>/...`（保留前缀）
转发到该 socket**。因此 `gateway.py`：
- 绑定 `<target>/app.sock`（chmod 0666）；
- 去掉 `/app/orcaslicer` 前缀后，反代 HTTP + WebSocket 到 `127.0.0.1:13000`（KasmVNC）；
- **注入上游 `Authorization: Basic abc:orcaslicer`**，于是浏览器永远收不到 401、不弹登录框（和 Chrome 一样）。

### 4. 分辨率随窗口自适应
KasmVNC 客户端默认把 WebSocket 拼成 `wss://<host>:<port>/websockify`（丢了前缀），所以必须通过 URL 参数：
- `path=app/orcaslicer/websockify` —— 让 WS 走统一网关；
- `resize=remote` —— 会话分辨率跟随浏览器视口动态变化（配合服务端 `desktop.allow_resize: true`）。

.icon 桌面入口 URL：
```
/app/orcaslicer/vnc.html?path=app/orcaslicer/websockify&autoconnect=1&resize=remote
```

### 5. .fpk 格式（逆向自官方/第三方包，并用真实包校验）
- `.fpk` = **tar.gz**，成员为「包根」条目、**没有顶层目录**；
- 包根含：`manifest`、`app.tgz`、`cmd/`、`config/`、`ui/`、`wizard/`、`ICON.PNG`、`ICON_256.PNG`；
- `app.tgz` 是「安装后放到 `target/` 的那份内容」（本包里含 `app/docker-compose.yaml`、`ui/`、
  `gateway.py`、`config/`，以及**内置的 docker 镜像 `image.tar`**）；
- `manifest.checksum = md5(app.tgz)`（必须每次重算）。
- 安装时以 root 运行 `cmd/install_callback`（`docker load image.tar`）、`cmd/main start`
  （起容器 + 起网关）。桌面入口由安装器根据 `ui/config` 生成到数据库 `app_service`/`app_open`。

---

### 6. NAS 目录挂载（本地定制，**不要写进 fpk**）
- 发行包里的 `app/docker-compose.yaml` 只保留通用的三个卷（`shares/{config,cache,models}`），
  **不要**把某台机器特有的宿主路径（如 `/vol1/.../deta-files`）写进 fpk——那样不利于分发。
- 用户装完后，自行在 **已安装应用的 compose**（`/volN/@appcenter/orcaslicer/app/docker-compose.yaml`）
  里追加 `- 宿主路径:/models/子目录` 即可；也可通过飞牛 Docker 界面加映射。
- 为便于在 OrcaSlicer 的文件对话框里找到这些目录，`start.sh` 只固定加一个 GTK 书签
  **`/models`**（通用）；用户把目录挂到 `/models` 下，进这个书签即可看到。

---

## 构建与运行

### 前置
- 在飞牛（Debian 12）上的 docker 环境；本机需能访问 docker。
- 构建镜像需要联网（apt 走镜像源、`--network host`，因为容器内 DNS 不稳）。

### 1. 构建镜像
```bash
cd orcaSlicerFnos
DOCKER_BUILDKIT=1 docker build --network host -t orcaslicer:2.4.2 .
```

### 2. 本地调试（不装到飞牛）
```bash
docker compose up -d
# 浏览器访问 http://<NAS_IP>:13000  （KasmVNC 登录 abc / orcaslicer；经网关接入时无需登录）
```

### 3. 打包 .fpk
```bash
bash build_fpk.sh
# 产物：dist/orcaslicer_2.4.2_all.fpk （内置镜像，约 600MB，可离线安装）
```

### 4. 安装到 fnOS
- 应用中心 → **手动安装** → 选存储空间 → 上传 `dist/orcaslicer_2.4.2_all.fpk` → 同意“未经验证应用”。
- 装完飞牛桌面出现 **OrcaSlicer** 图标，点击内嵌打开、无需登录。

---

## 升级 OrcaSlicer 版本
1. 换 `Orca.AppImage`（保持文件名或改 Dockerfile 中的 COPY 名）。
2. 改 `Dockerfile` 里的版本注释无所谓；改 `build_fpk.sh` 顶部 `VER=` 与 `IMG=`，以及
   包内 `app/docker-compose.yaml`（`image: orcaslicer:<ver>`）。
3. 重新 `docker build` + `bash build_fpk.sh`。

---

## 血泪坑（改代码前务必看）

| 现象 | 原因 / 解决 |
|---|---|
| 启动报 `Switching Orca Slicer to language en_US failed` | 镜像缺 locale。Dockerfile 里装 `locales` 并 `locale-gen en_US.UTF-8`（已修）。 |
| 容器反复重启，日志 `:1 is taken because of /tmp/.X1-lock` | 上次异常退出残留 X 锁。`start.sh` 启动前 `rm -f /tmp/.X1-lock /tmp/.X11-unix/X1`（已修）。 |
| `kasmvncserver` 报 `No users configured and prompting is prohibited` | 即使不需要登录，wrapper 也要求存在用户项。`start.sh` 仍创建一个 `.kasmpasswd`（已修）。 |
| WebSocket 连不上、卡在蓝色启动页 | 客户端默认 ws 路径丢了前缀。必须 `?path=app/orcaslicer/websockify`（已修）。 |
| 有滚动条 / 最大化超出窗口 | 客户端 `resize=off`。加 `?resize=remote`（已修）。 |
| 打开报 `invalid token` | `app_open.open_type` 必须是 `iframe`（不是 `url`）；`app_service.type` 也要 `iframe` + `gateway_prefix`/`gateway_socket`。 |
| 打包后文件权限是 `000` | 该环境 shell 的 `umask` 可能是 0777。`build_fpk.sh` 已 `umask 022` 并显式 `chmod`，注意别再引入。 |
| 网关报 `setsockopt ... Operation not supported` | Unix socket 上不要设 `disable_nagle_algorithm`/TCP_NODELAY（gateway 已用 `BaseRequestHandler`）。 |
| 直接改了安装的应用不生效 | 需要 `systemctl restart trim_app_center`；桌面还要 `Ctrl+F5`。 |

---

## 已知问题：3D 模型旋转略卡（VNC 编码瓶颈，非渲染）

**现象**：OrcaSlicer 里缩放 3D 视图流畅，但旋转（拖动转向）略卡、掉帧。

**诊断**（已确认）：
- 3D 是**硬件渲染**的，不是软件。容器内 `DISPLAY=:1 glxinfo -B`：
  `OpenGL renderer: AMD ... (radeonsi, renoir, ACO ...)`，`Accelerated: yes`。
- 瓶颈在 **KasmVNC 的帧编码（CPU）**：
  - 缩放 = 整屏均匀变化 → KasmVNC 走“视频/缩放”快速路径，编码便宜 → 流畅。
  - 旋转 = 非均匀变化，模型边缘/抗锯齿产生大量细碎、移动的小区域 → 逐矩形编码，每帧编码块数与 CPU 激增 → 卡。
- KasmVNC 日志：`Hardware video encoding acceleration capability: unavailable`
  → **没有硬件视频编码**，全靠 CPU。输命令：`docker exec orcaslicer grep -i "Hardware video encoding" /root/.vnc/*.log`。

**已尝试的缓解**：
- 镜像装 `libva2 libva-drm2 mesa-va-drivers`（容器内可见 `radeonsi_drv_video.so`），但 KasmVNC 仍不启用；
  加 `LIBVA_DRIVER_NAME=radeonsi` 也无效 → 已移除该环境变量（避免强制，分发更干净）。
- `start.sh` 的 `kasmvnc.yaml` 加了编码调参：`encoding.max_frame_rate=60`、
  `video_encoding_mode.enter/exit... {time_threshold:2, area_threshold:20%}` → **实测无明显改善**。
- WebKit 合成环境变量（`WEBKIT_DISABLE_COMPOSITING_MODE=1` 等）是省**内存**的，与本问题无关。

**结论**：这是 VNC 串流对“非均匀运动”的固有短板，不是配置错误。Web 端缩放/滚动顺、旋转/复杂动画卡属正常。

**对非 AMD 平台的影响**：上述改动**无负面影响**。`mesa-va-drivers` 在 Intel 上不提供 VAAPI 驱动（Intel 需额外
`intel-media-va-driver-non-free`；NVIDIA 需 `nvidia-vaapi-driver`）；编码调参与 WebKit/书签均通用。Intel 平台
补上对应驱动后 KasmVNC 硬编更可能生效。

**后续可选方向**（未实施）：
1. 降低分辨率/画质（`RESOLUTION=1600x900`，或客户端 URL 加 `&quality=4`）——少编码像素，旋转更顺，清晰度下降。
2. 给 Intel 机器加 `intel-media-va-driver-non-free`。
3. 换串流方案（xpra / 自建 H.264），改善动态画面，但需绕开飞牛统一网关，工作量大。

---

## 关键参数速查（改密码/端口时几处要同步）

- `VNC_USER=abc`、`VNC_PASSWORD=orcaslicer`：容器 `start.sh` 与 `docker-compose*.yaml` 环境变量。
- 网关注入的凭据 `ORCA_AUTH`（默认 `abc:orcaslicer`）：在 `gateway.py`，**要和上面的密码一致**。
- 端口：容器内 KasmVNC `:3000`；宿主/网关上游 `13000`（`gateway.py` 的 `ORCA_PORT`、
  compose 的 `13000:3000`、manifest 的 `service_port`）。
- 应用名/前缀：`orcaslicer` / `/app/orcaslicer`（`gateway.py` 的 `PREFIX`、`ui/config`、
  桌面 DB 的 `gateway_prefix`）。

---

## 数据库注册（非 fpk 安装时的参考）
用 fpk 安装会自动写；若要手动注册，关键三张表：
- `app`：`app_name='orcaslicer'`, `micro_app=t`, `is_docker=f`, `status='running'`, `path='/var/apps/orcaslicer'`。
- `app_service`：`type='iframe'`, `url='http://${host}/app/orcaslicer/vnc.html?path=app/orcaslicer/websockify&autoconnect=1&resize=remote'`,
  `gateway_socket='/var/apps/orcaslicer/target/app.sock'`, `gateway_prefix='/app/orcaslicer'`, `icon='ui/images/icon_{0}.png'`,
  `control='{"show":0,"showRoute":0,"auth":1,"port":2,"path":2,"fullUrl":2,"accessPerm":"readonly","portPerm":"hidden","pathPerm":"hidden","fullUrlPerm":"hidden"}'`。
- `app_open`：`open_type='iframe'`, `content='orcaslicer.Application'`。
改完 `systemctl restart trim_app_center.service`。
