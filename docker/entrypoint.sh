#!/usr/bin/env bash
# PiliPlus Android 构建入口, 在 docker 镜像内运行.
#
# 源码先复制到容器内的构建目录再编译, 宿主工作区不会被写入 dart / gradle 缓存.
#
# 环境变量:
#   SRC  源码目录, 默认 /src, 该目录没有 git 仓库时退回当前目录.
#   WORK 容器内构建目录, 默认 /work.
#   OUT  产物输出目录, 默认 /out.

set -euo pipefail

log() {
    printf '[android-build] %s\n' "$*"
}

die() {
    printf '[android-build] 错误: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
用法: android-build [选项] [-- <额外的 flutter build 参数>]

选项:
  --release           构建 Release APK (默认)
  --debug             构建 Debug APK
  --dev               使用 dev 变体, 包名带 .dev 后缀
  --abi <arm64|armv7|x86_64>
                      目标 ABI, 默认 arm64 (即 arm64-v8a)
  -h, --help          显示本帮助
EOF
}

MODE=release
DEV=0
ABI=arm64
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --release) MODE=release ;;
        --debug) MODE=debug ;;
        --dev) DEV=1 ;;
        --abi) ABI="${2:?--abi 需要一个取值}" ; shift ;;
        --abi=*) ABI="${1#*=}" ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        *) die "未知参数: $1 (用 -- 分隔 flutter build 的参数)" ;;
    esac
    shift
done

case "$ABI" in
    arm64) TARGET_PLATFORM=android-arm64 ;;
    armv7 | android-arm) TARGET_PLATFORM=android-arm ;;
    x86_64 | amd64 | x64 | android-x64) TARGET_PLATFORM=android-x64 ;;
    *) die "不支持的 ABI: $ABI" ;;
esac

SRC="${SRC:-/src}"
if [ ! -d "$SRC/.git" ]; then
    SRC="$(pwd)"
fi
WORK="${WORK:-/work}"
OUT="${OUT:-/out}"
if ! mkdir -p "$OUT" 2>/dev/null; then
    OUT="$HOME/out"
    mkdir -p "$OUT"
fi

[ -d "$SRC/.git" ] || die "源码目录不是 git 仓库: $SRC"

log "源码目录: $SRC"
log "构建目录: $WORK"
log "产物目录: $OUT"
log "模式: ${MODE}, dev=${DEV}, ABI=${ABI} (${TARGET_PLATFORM})"

mkdir -p "$WORK"
if [ -d "$WORK/src/.git" ]; then
    log "增量同步源码, 复用上次构建缓存"
    rsync -a --no-owner --no-group --delete \
        --exclude '/build/' \
        --exclude '/.dart_tool/' \
        --exclude '/.flutter-plugins' \
        --exclude '/.flutter-plugins-dependencies' \
        --exclude '/android/.gradle/' \
        --exclude '/android/app/.cxx/' \
        --exclude '/android/local.properties' \
        --exclude '/.tmp/' \
        --exclude '/.agents/' \
        --exclude '/.idea/' \
        --exclude '/.vscode/' \
        "$SRC/" "$WORK/src/"
else
    rm -rf "$WORK/src"
    log "复制源码到构建目录"
    git clone --quiet "$SRC" "$WORK/src"
fi

cd "$WORK/src"

export FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/flutter}"
export GITHUB_WORKSPACE="$WORK/src"
export GITHUB_ENV="$WORK/github_env"
: >"$GITHUB_ENV"

if [ -f "${FLUTTER_ROOT}/.piliplus-patched" ]; then
    log "Flutter SDK 补丁已固化在镜像中, 跳过打补丁"
else
    log "给 Flutter SDK 打补丁"
    pwsh -NoLogo -NoProfile -File lib/scripts/patch.ps1 android
fi

log "写入版本信息"
pwsh -NoLogo -NoProfile -File lib/scripts/build.ps1 android
grep -m1 '^version:' pubspec.yaml || true

log "同步 Dart 依赖"
flutter pub get

BUILD_ARGS=(--no-pub --target-platform "$TARGET_PLATFORM")
if [ "$MODE" = release ]; then
    BUILD_ARGS+=(--release --split-per-abi --dart-define-from-file=pili_release.json)
else
    BUILD_ARGS+=(--debug)
fi
if [ "$DEV" -eq 1 ]; then
    BUILD_ARGS+=(--android-project-arg dev=1)
fi

log "开始构建: flutter build apk ${BUILD_ARGS[*]} ${EXTRA_ARGS[*]:-}"
START_SECONDS=$SECONDS
flutter build apk "${BUILD_ARGS[@]}" "${EXTRA_ARGS[@]}"
log "构建耗时 $((SECONDS - START_SECONDS)) 秒"

shopt -s nullglob
APKS=("$WORK/src/build/app/outputs/flutter-apk"/*.apk)
shopt -u nullglob
[ ${#APKS[@]} -gt 0 ] || die "构建完成但未找到 APK 产物"

mkdir -p "$OUT"
cp -f "${APKS[@]}" "$OUT/"

log "产物:"
ls -lh "$OUT"/*.apk
