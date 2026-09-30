# orcaSlicerFnos

把 **[OrcaSlicer](https://github.com/OrcaSlicer/OrcaSlicer)** 打包成 **飞牛 fnOS** 应用：以
Docker + KasmVNC 方式运行，**可从飞牛 Web 桌面内嵌打开、无需登录、分辨率随窗口自适应**，
并打包成可离线安装的 `.fpk`。

> 非官方第三方打包。OrcaSlicer 本体版权归其作者所有（AGPL-3.0）；本仓库只包含打包脚本与配置，
> 不含 OrcaSlicer 二进制（构建时从上游下载）。

---

## 特性

- 🖥️ **内嵌飞牛桌面**：走飞牛「统一网关」，点在桌面图标即在网页内打开，不弹端口页。
- 🔓 **免登录**：网关自动向上游注入凭据，浏览器不会出现 KasmVNC 登录框（与官方 Chrome 应用一致）。
- 📐 **分辨率自适应**：拖动/最大化窗口时内部会话分辨率动态跟随（`resize=remote`）。
- ⚡ **GPU 加速**：透传 `/dev/dri`，3D 视图走核显（AMD/Intel `radeonsi`/`i915` 等）。
- 📦 **可离线分发**：`.fpk` 内置 Docker 镜像，应用中心「手动安装」即可，无需联网。
- 🗂️ **访问 NAS 文件**：把目录挂到容器里的 `/models`，在 OrcaSlicer 文件对话框点「模型」即可。

---

## 工作原理

```
浏览器(飞牛桌面) ── iframe ──▶ /app/orcaslicer/vnc.html
                                   │  (飞牛 nginx + trim_http_cgi，保留前缀)
                                   ▼
                         target/app.sock  (gateway.py，注入 Authorization)
                                   │  HTTP + WebSocket 反向代理
                                   ▼
                         127.0.0.1:13000 ─▶ KasmVNC(:3000) + openbox + OrcaSlicer
                                                        （容器内，透传 /dev/dri）
```

- 底包 `ubuntu:24.04`：OrcaSlicer 官方 AppImage 要求 `GLIBC_2.38`，而 fnOS(Debian 12) 只有 2.36。
- `gateway.py`：绑定 `<target>/app.sock`，剥掉 `/app/orcaslicer` 前缀后反代到 KasmVNC，并注入
  登录凭据；这是飞牛 microApp 的统一接入方式。
- KasmVNC 客户端默认把 WS 拼成 `/websockify`（丢前缀），所以桌面入口 URL 带
  `?path=app/orcaslicer/websockify&autoconnect=1&resize=remote`。

---

## 目录结构

```
orcaSlicerFnos/
├── Dockerfile            # ubuntu:24.04 + KasmVNC(deb) + OrcaSlicer(AppImage)
├── root/usr/local/bin/start.sh   # 容器入口：KasmVNC + openbox + OrcaSlicer
├── gateway.py            # 宿主机统一网关（app.sock → KasmVNC）
├── cmd-main              # fnOS 生命周期脚本（容器 + 网关）
├── build_fpk.sh          # 生成 dist/orcaslicer_<ver>_all.fpk（内置镜像）
├── docker-compose.yml    # 本地调试（13000:3000）
├── fetch-deps.sh         # 下载未入库的大文件（AppImage / kasmvnc deb）
├── AGENTS.md             # 开发/维护文档（架构、踩坑、参数速查）
└── icon.png  kasmvnc_noble.deb
```

---

## 快速开始

### 1. 取依赖（仓库不含大文件）
```bash
git clone https://github.com/DetaLee233/orcaSlicerFnos.git
cd orcaSlicerFnos
bash fetch-deps.sh          # 下载 Orca.AppImage 与 kasmvnc_noble.deb（带 sha256 校验）
```

### 2. 构建镜像
```bash
DOCKER_BUILDKIT=1 docker build --network host -t orcaslicer:2.4.2 .
```

### 3. 本地试跑（可选）
```bash
docker compose up -d
# 浏览器打开 http://<NAS_IP>:13000  （KasmVNC 登录 abc / orcaslicer）
```

### 4. 打 .fpk
```bash
bash build_fpk.sh
# 产物：dist/orcaslicer_2.4.2_all.fpk
```

### 5. 安装到 fnOS
应用中心 → **手动安装** → 选存储空间 → 上传 `.fpk` → 同意「未经验证应用」→
桌面出现 **OrcaSlicer** 图标，点击内嵌打开。

---

## 访问 NAS 文件

发行包只把容器内的 **`/models`** 作为书签暴露。装完后在**该应用的 compose**
（`/volN/@appcenter/orcaslicer/app/docker-compose.yaml`）里加一条映射即可：

```yaml
    volumes:
      - /vol1/1000/你的目录:/models/你的名字
```

重建容器后，OrcaSlicer 文件对话框点左侧 **模型 → 你的名字** 即可看到。
（也可用飞牛 Docker 界面加映射。）

---

## 配置

| 项 | 位置 | 默认 |
|---|---|---|
| VNC 用户名/密码 | 容器 `start.sh`、compose 环境变量；网关注入用 `gateway.py` 的 `ORCA_AUTH` | `abc` / `orcaslicer` |
| 端口 | 容器内 `3000`，宿主/网关上流 `13000` | — |
| 分辨率 | `RESOLUTION`（配合 `resize=remote` 自适应） | `1920x1080` |
| WebKit 内存优化 | `start.sh`：`WEBKIT_DISABLE_COMPOSITING_MODE` 等 | 已开 |

> 改密码要**同时**改 `VNC_PASSWORD` 和 `gateway.py` 的 `ORCA_AUTH`，否则网关注入的凭据对不上。

---

## 升级 OrcaSlicer

1. 换掉 `Orca.AppImage`（或改文件名并同步 Dockerfile）。
2. 改 `build_fpk.sh` 顶部 `VER=`、`IMG=`，以及包内 `app/docker-compose.yaml` 的 `image:`。
3. 重新 `docker build` + `bash build_fpk.sh`。

---

## 已知问题

- **3D 旋转略卡、缩放流畅**：这是远端的 **KasmVNC CPU 编码**瓶颈（旋转是非均匀运动，逐块编码重），
  不是渲染问题（已确认 3D 走硬件 `radeonsi`）。缓解手段与结论见 [AGENTS.md](AGENTS.md#已知问题3d-模型旋转略卡vnc-编码瓶颈非渲染)。
- **AMD 核显硬件视频编码**：KasmVNC 不支持，仍走 CPU（已装 VAAPI 库备用，Intel 平台补
  `intel-media-va-driver-non-free` 更可能生效）。

---

## 免责声明

- 本项目为社区打包，与 OrcaSlicer 官方、飞牛官方均无关联。
- OrcaSlicer 及其依赖的著作权/许可归各自作者所有（OrcaSlicer 为 AGPL-3.0）。
- 使用风险自负，尤其注意应用以 root 运行并透传了 GPU 设备。
