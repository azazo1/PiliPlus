# Android 独立构建环境

在 Docker 容器里构建 PiliPlus 的 Android APK, 本机不需要安装 Flutter 与 Android SDK.
镜像内容对齐 `.github/workflows/build.yml` 的 android job, 构建步骤直接复用
`lib/scripts/patch.ps1` 与 `lib/scripts/build.ps1`.

## 环境内容

| 组件 | 版本 |
| --- | --- |
| Ubuntu | 24.04 |
| JDK | 17 (openjdk-17-jdk-headless) |
| Flutter | 取自 `.fvmrc` (当前 3.44.8) |
| Android compileSdk | 36 |
| build-tools | 36.0.0 |
| NDK | 28.2.13676358 |
| PowerShell | 7.4.6 |

Flutter 版本由 `docker/run.py` 从 `.fvmrc` 读取后透传给镜像构建, 其余版本在
`docker/Dockerfile` 的 `ARG` 里调整.

## 使用

前置: 已安装并启动 Docker, 以及 Python 3.

```shell
# 默认构建 Release APK, 目标 ABI 为 arm64 (arm64-v8a)
just build android-docker

# Debug 构建
just build android-docker --debug

# dev 变体, 包名带 .dev 后缀, 可与正式包共存
just build android-docker --debug --dev

# 其它 ABI
just build android-docker --abi armv7
```

等价的直接调用:

```shell
python3 docker/run.py --release --abi arm64
```

首次运行会自动构建镜像, 后续复用已有镜像. Flutter 版本变化或需要重建镜像时:

```shell
just build android-docker --rebuild
```

需要排查容器环境时可以进入 shell:

```shell
python3 docker/run.py --shell
```

## 缓存与快速重建

镜像和构建缓存都是持久的, 源码改动后再次构建只做增量工作:

| 位置 | 作用 |
| --- | --- |
| Docker 镜像 `piliplus-android-builder:<Flutter 版本>` | JDK, Android SDK, Flutter SDK 以及固化的 Flutter 补丁 |
| `.tmp/docker-cache/gradle` | Gradle 依赖与编译缓存 |
| `.tmp/docker-cache/pub` | Pub 依赖缓存 |
| `.tmp/docker-cache/work` | 上次构建的源码副本, 保留 `build/` 与 `.dart_tool/` |

`lib/scripts` 下的补丁文件变化时, `docker/run.py` 会比对镜像 label 上的指纹并自动重建镜像,
其余情况直接复用已有镜像. 想彻底清空缓存时删掉对应目录即可:

```shell
rm -rf .tmp/docker-cache
```

## 产物

APK 输出到 `.tmp/docker-out/`, 该目录已被 `.gitignore` 覆盖.
Release 构建在没有 `android/key.properties` 时和 CI 的 PR 构建一样使用 debug 签名,
产物只能本地安装验证, 不能用于分发.

## 网络

国内网络可以直接给构建加上 Flutter 官方镜像源:

```shell
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
just build android-docker --rebuild
```

两个变量会同时传给镜像构建和容器内的 `flutter` 命令.
Gradle 的依赖下载仍走 `google()` 与 `mavenCentral()`, 必要时给 Docker 配置代理.

## devcontainer

`.devcontainer/devcontainer.json` 复用 `docker/run.py` 构建的同一个镜像, 不另外构建一份:

- `initializeCommand` 先执行 `python3 docker/run.py --build-only` 准备镜像;
- 容器启动后把本仓库挂到 `/workspaces/piliplus`, 并复用 `docker-cache` 下的 gradle 与 pub 缓存.

在 VS Code 里选择 "Reopen in Container" 后, 可以直接在容器终端执行:

```shell
android-build --debug
```

容器内 `SRC` 指向 `/workspaces/piliplus`, `OUT` 指向工作区的 `.tmp/docker-out`.
`image` 字段里写的是当前 Flutter 版本的 tag, `.fvmrc` 升级后需要同步修改.

## 架构与转译

只有一个镜像, 目标架构与宿主机一致 (Apple Silicon 上是 linux/arm64), JDK, Flutter, Gradle
都原生运行. Android 工具链里少数没有 arm64 版本的 x86_64 二进制需要转译:

| 文件 | 用途 | 来源 |
| --- | --- | --- |
| `aapt2` | 编译 Android 资源 | build-tools |
| `zipalign` | 对齐 APK | build-tools |
| `gen_snapshot` | Release 构建的 AOT 编译 | Flutter engine |

前两个在 arm64 镜像里补了 amd64 的 glibc 与动态链接器; `gen_snapshot` 通过
`linux-arm64 -> linux-x64` 目录链接暴露给 Flutter, 因此不需要为 release 单独维护 amd64 镜像.

macOS 上由 Docker Desktop 的 Rosetta 负责转译, 默认可用. arm64 Linux 宿主机需要注册
qemu binfmt (例如 `docker run --privileged --rm tonistiigi/binfmt --install amd64`),
否则 release 构建会在 `gen_snapshot` 处失败, debug 构建不受影响.

## 构建耗时与体积

| 场景 | 耗时 |
| --- | --- |
| 首次 (镜像构建加首次编译) | 15 到 20 分钟 |
| 源码改动后增量 debug | 约 1 分钟 |
| 源码改动后增量 release | 约 3 分钟 |

镜像约 8.5GB, 其中 NDK 2.2GB, Flutter 2.2GB, Android SDK 其余组件约 0.8GB.

## 说明

- 构建发生在容器内的源码副本上, 宿主工作区除了 `.tmp/docker-cache` (gradle 与 pub 缓存)
  和 `.tmp/docker-out` 之外不会被写入.
- `lib/scripts/patch.ps1` 会修改容器内的 Flutter SDK, 本机 SDK 不受影响.
- 镜像使用 `ubuntu` 用户构建, 避免 Flutter 与 Gradle 在 root 下运行产生的告警.
