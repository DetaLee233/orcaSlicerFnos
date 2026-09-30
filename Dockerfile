FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# Use a fast local mirror
RUN rm -f /etc/apt/sources.list.d/ubuntu.sources && \
    printf '%s\n' \
      'deb http://mirrors.aliyun.com/ubuntu/ noble main restricted universe multiverse' \
      'deb http://mirrors.aliyun.com/ubuntu/ noble-updates main restricted universe multiverse' \
      'deb http://mirrors.aliyun.com/ubuntu/ noble-security main restricted universe multiverse' \
      > /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils \
      openbox xterm \
      libgl1 libopengl0 libglu1-mesa libglx-mesa0 libegl-mesa0 libgl1-mesa-dri libgbm1 \
      libgtk-3-0t64 libwebkit2gtk-4.1-0 libjavascriptcoregtk-4.1-0 \
      libgomp1 libusb-1.0-0 libsecret-1-0 libcurl4t64 \
      libnss3 libxss1 libasound2t64 \
      locales \
      libva2 libva-drm2 mesa-va-drivers \
      fonts-noto-cjk fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Generate locales OrcaSlicer expects
RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/; s/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en

# KasmVNC (Ubuntu Noble build)
COPY kasmvnc_noble.deb /tmp/kasmvnc_noble.deb
RUN apt-get update && apt-get install -y --no-install-recommends /tmp/kasmvnc_noble.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/kasmvnc_noble.deb

# OrcaSlicer AppImage (extracted, no FUSE needed at runtime)
COPY Orca.AppImage /tmp/Orca.AppImage
RUN chmod +x /tmp/Orca.AppImage \
    && /tmp/Orca.AppImage --appimage-extract \
    && mv squashfs-root /opt/orcaslicer \
    && rm -f /tmp/Orca.AppImage

COPY root/ /
RUN chmod +x /usr/local/bin/start.sh

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/start.sh"]
