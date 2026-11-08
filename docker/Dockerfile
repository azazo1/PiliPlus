# syntax=docker/dockerfile:1.7
# PiliPlus Android 独立构建环境.
#
# 在容器里构建 arm64-v8a APK, 与 .github/workflows/build.yml 的 android job 对齐:
#   JDK 17, Flutter 3.44.8, platforms;android-36, build-tools;36.0.0,
#   ndk;28.2.13676358, cmake;3.22.1, 以及 PowerShell 7 (lib/scripts/*.ps1 依赖 pwsh).
#
# 用法见 docker/README.md.

ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

# BuildKit / buildx 会自动注入 TARGETARCH; 不走 BuildKit 的旧式构建拿不到它,
# 所以下面一律用 `${TARGETARCH:-$(dpkg --print-architecture)}` 兜底.
ARG TARGETARCH
ARG FLUTTER_VERSION=3.44.8
ARG CMDLINE_TOOLS_VERSION=13114758
ARG PWSH_VERSION=7.4.6
ARG ANDROID_PLATFORMS=36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_NDK=28.2.13676358
ARG ANDROID_CMAKE=3.22.1
# 国内网络可在构建时传 --build-arg FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
ARG FLUTTER_STORAGE_BASE_URL=
ARG PUB_HOSTED_URL=
# 镜像输入指纹, 由 docker/run.py 计算, 只用于 label, 不改变安装内容.
ARG PATCH_HASH=unset
ARG BUILD_INPUT_HASH=unset

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    JAVA_HOME=/opt/java17 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    FLUTTER_ROOT=/opt/flutter \
    PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# 系统依赖. apt 的索引与下载缓存放进 BuildKit cache mount, 不进入镜像层.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip zip xz-utils bzip2 file jq rsync \
        openjdk-17-jdk-headless libicu78; \
    ln -sfn "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /opt/java17; \
    rm -rf /usr/share/doc /usr/share/man /var/cache/apt/archives/*; \
    java -version

# PowerShell 7: 与 CI 一致, 直接复用 lib/scripts 下的 ps1 脚本.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${arch}" in \
        arm64) pwsh_arch=arm64 ;; \
        amd64) pwsh_arch=x64 ;; \
        *) echo "不支持的架构: ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/pwsh.tar.gz \
        "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-${pwsh_arch}.tar.gz"; \
    mkdir -p /opt/powershell; \
    tar -xzf /tmp/pwsh.tar.gz -C /opt/powershell; \
    rm -f /tmp/pwsh.tar.gz; \
    chmod 755 /opt/powershell/pwsh; \
    ln -sf /opt/powershell/pwsh /usr/local/bin/pwsh; \
    pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'

# Android build-tools 的 aapt2 / zipalign 只有 x86_64 版本, arm64 容器里由
# Rosetta (macOS) 或 qemu binfmt (Linux) 转译执行, 需要 amd64 的 glibc 与动态链接器.
# 其余工具链 (JDK, Flutter, Gradle) 仍然是原生 arm64.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    if [ "${arch}" = "arm64" ]; then \
        codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"; \
        printf 'deb [arch=amd64] http://archive.ubuntu.com/ubuntu %s main universe\n' "${codename}" > /etc/apt/sources.list.d/amd64.list; \
        printf 'deb [arch=amd64] http://archive.ubuntu.com/ubuntu %s-updates main universe\n' "${codename}" >> /etc/apt/sources.list.d/amd64.list; \
        printf 'deb [arch=amd64] http://archive.ubuntu.com/ubuntu %s-security main universe\n' "${codename}" >> /etc/apt/sources.list.d/amd64.list; \
        apt-get update; \
        cd /tmp; \
        apt-get download libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64 zlib1g:amd64; \
        for deb in *.deb; do dpkg -x "$deb" /; done; \
        rm -f /tmp/*.deb /etc/apt/sources.list.d/amd64.list; \
        rm -rf /var/cache/apt/archives/*; \
        mkdir -p /lib64; \
        ln -sf /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2; \
    fi

# 目录一开始就归属构建用户, 后续安装过程不再需要整树 chown (那会让 overlay 复制整棵树).
RUN install -d -o ubuntu -g ubuntu /opt/flutter /opt/android-sdk /work

ENV HOME=/home/ubuntu
USER ubuntu

# Android 命令行工具与 SDK 组件, 以构建用户身份安装.
RUN set -eux; \
    mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"; \
    curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"; \
    unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools"; \
    mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest"; \
    rm -f /tmp/cmdline-tools.zip; \
    yes | sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null 2>&1 || true; \
    sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" \
        "platform-tools" \
        "platforms;android-${ANDROID_PLATFORMS}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "ndk;${ANDROID_NDK}" \
        "cmake;${ANDROID_CMAKE}"

# Flutter SDK: 需要 git 历史, patch.ps1 会 cherry-pick 上游修复提交.
RUN set -eux; \
    if [ -z "${FLUTTER_STORAGE_BASE_URL:-}" ]; then unset FLUTTER_STORAGE_BASE_URL; fi; \
    if [ -z "${PUB_HOSTED_URL:-}" ]; then unset PUB_HOSTED_URL; fi; \
    git clone --filter=blob:none -b "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"; \
    git config --global --add safe.directory "${FLUTTER_ROOT}"; \
    flutter --version; \
    flutter config --no-analytics >/dev/null; \
    flutter precache --android; \
    rm -rf "${FLUTTER_ROOT}/.pub-cache"

# 项目对 Flutter SDK 的补丁固化进镜像, 运行时不必重复 cherry-pick 与 apply.
# 补丁文件变化时该层重建, 由 docker/run.py 比较 PATCH_HASH 触发.
COPY --chown=ubuntu:ubuntu lib/scripts/ /tmp/piliplus/lib/scripts/
RUN set -eux; \
    echo "Flutter 补丁集合: ${PATCH_HASH}"; \
    cd /tmp/piliplus; \
    GITHUB_WORKSPACE=/tmp/piliplus pwsh -NoLogo -NoProfile -File lib/scripts/patch.ps1 android; \
    touch "${FLUTTER_ROOT}/.piliplus-patched"; \
    rm -rf /tmp/piliplus

COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/android-build

# Flutter 的 AOT 编译器 gen_snapshot 只有 x86_64 版本, arm64 host 上 Flutter 会去找
# linux-arm64 目录并失败. 这里链接到 linux-x64, 让 release 构建经由 Rosetta 执行,
# 不必为了 release 再维护一份完整的 amd64 镜像.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    if [ "${arch}" = "arm64" ]; then \
        for dir in "${FLUTTER_ROOT}"/bin/cache/artifacts/engine/android-*-release \
                   "${FLUTTER_ROOT}"/bin/cache/artifacts/engine/android-*-profile; do \
            [ -d "${dir}/linux-x64" ] || continue; \
            [ -e "${dir}/linux-arm64" ] || ln -s linux-x64 "${dir}/linux-arm64"; \
        done; \
    fi

WORKDIR /home/ubuntu
# 不设 ENTRYPOINT, 便于在 devcontainer 里直接进入 shell.
# 构建入口: android-build --debug|--release [--abi arm64] [-- <flutter build 参数>]
CMD ["bash"]

LABEL piliplus.patch-hash="${PATCH_HASH}" \
      piliplus.build-input-hash="${BUILD_INPUT_HASH}"
