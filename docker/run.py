#!/usr/bin/env python3
"""在 Docker 容器里构建 PiliPlus Android APK.

宿主只负责组织 docker 命令, 真正的构建发生在 docker/entrypoint.sh 里.
源码以只读方式挂载进容器, 容器内复制一份再编译, 宿主工作区不会产生
dart / gradle 缓存.

典型用法:

    python3 docker/run.py --release --abi arm64
    python3 docker/run.py --debug --dev
    python3 docker/run.py --rebuild

国内网络首次构建可以先设置镜像源:

    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \\
    PUB_HOSTED_URL=https://pub.flutter-io.cn \\
    python3 docker/run.py --rebuild
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCKERFILE = ROOT / "docker" / "Dockerfile"
MAIN_ENGINE = "docker"

# CI 会把同一套指纹的镜像推到 GHCR, 本地默认优先复用它, 找不到才本地构建.
DEFAULT_REGISTRY = os.environ.get(
    "PILIPLUS_DOCKER_REGISTRY", "ghcr.io/azazo1/piliplus-android-builder"
)

SUPPORTED_ABIS = ("arm64", "armv7", "x86_64")


def log(message: str) -> None:
    print(f"[android-build] {message}", flush=True)


def die(message: str) -> None:
    print(f"[android-build] 错误: {message}", file=sys.stderr, flush=True)
    raise SystemExit(1)


def flutter_version() -> str:
    """从 .fvmrc 读取 Flutter 版本, 缺失时退回 pubspec.yaml 的约束."""
    fvmrc = ROOT / ".fvmrc"
    if fvmrc.is_file():
        try:
            data = json.loads(fvmrc.read_text(encoding="utf-8"))
            version = str(data.get("flutter", "")).strip()
            if version:
                return version
        except json.JSONDecodeError:
            pass

    pubspec = ROOT / "pubspec.yaml"
    if pubspec.is_file():
        for line in pubspec.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("flutter:"):
                return line.split(":", 1)[1].strip().strip('"').strip("'")
    die("无法确定 Flutter 版本, 请检查 .fvmrc 或 pubspec.yaml")


def patch_set_hash() -> str:
    """计算 lib/scripts 里补丁集合的指纹, 用于判断镜像里的固化补丁是否过期."""
    scripts = ROOT / "lib" / "scripts"
    files = sorted(
        path
        for path in scripts.iterdir()
        if path.is_file() and (path.suffix == ".patch" or path.name == "patch.ps1")
    )
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.name.encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()[:12]


def build_input_hash() -> str:
    """Dockerfile 与入口脚本的指纹, 两者变化时镜像必须重建."""
    digest = hashlib.sha256()
    for path in (DOCKERFILE, ROOT / "docker" / "entrypoint.sh"):
        digest.update(path.name.encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()[:12]


def image_label(image: str, key: str) -> str | None:
    result = subprocess.run(
        [
            MAIN_ENGINE,
            "image",
            "inspect",
            "--format",
            '{{ index .Config.Labels "' + key + '" }}',
            image,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def image_reference(version: str, patch_hash: str, input_hash: str) -> str:
    """本地与 CI 使用同一个 tag, 由输入指纹组成, 内容一致才命中."""
    return f"{version}-{patch_hash}-{input_hash}"


def remote_exists(remote: str) -> bool:
    result = subprocess.run(
        [MAIN_ENGINE, "manifest", "inspect", remote],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def pull_remote(remote: str, local: str) -> bool:
    log(f"从远端拉取镜像 {remote}")
    result = subprocess.run([MAIN_ENGINE, "pull", remote], cwd=ROOT)
    if result.returncode != 0:
        log("拉取失败, 改为本地构建")
        return False
    subprocess.run(
        [MAIN_ENGINE, "tag", remote, local],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
    )
    return True


def image_matches(image: str, patch_hash: str, input_hash: str) -> bool:
    if not image_exists(image):
        return False
    return (
        image_label(image, "piliplus.patch-hash") == patch_hash
        and image_label(image, "piliplus.build-input-hash") == input_hash
    )


def resolve_secrets(explicit: str | None) -> Path | None:
    """定位签名密钥目录.

    优先用显式路径, 其次是当前项目根下的 secrets/. 在 git worktree 里构建时,
    该目录通常不存在, 于是回退到主工作树的 secrets/, 避免静默退回 debug 签名.
    """
    if explicit:
        path = Path(explicit).expanduser().resolve()
        return path if path.is_dir() else None

    local = ROOT / "secrets"
    if local.is_dir():
        return local

    result = subprocess.run(
        ["git", "-C", str(ROOT), "worktree", "list", "--porcelain"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        if line.startswith("worktree "):
            candidate = Path(line[len("worktree "):]) / "secrets"
            if candidate.is_dir():
                return candidate
    return None


def run(command: list[str], *, env: dict[str, str] | None = None) -> None:
    log("执行: " + " ".join(command))
    completed = subprocess.run(command, cwd=ROOT, env=env)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


def image_exists(image: str) -> bool:
    result = subprocess.run(
        [MAIN_ENGINE, "image", "inspect", image],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def parse_argv(argv: list[str]) -> tuple[list[str], list[str]]:
    if "--" in argv:
        index = argv.index("--")
        return argv[:index], argv[index + 1 :]
    return argv, []


def main() -> None:
    own_args, extra_args = parse_argv(sys.argv[1:])

    parser = argparse.ArgumentParser(
        description="在 Docker 容器里构建 PiliPlus Android APK.",
        epilog="使用 `--` 分隔的剩余参数会原样传给 flutter build.",
    )
    parser.add_argument("--release", dest="mode", action="store_const", const="release")
    parser.add_argument("--debug", dest="mode", action="store_const", const="debug")
    parser.add_argument("--dev", action="store_true", help="构建 dev 变体, 包名带 .dev 后缀")
    parser.add_argument("--abi", default="arm64", choices=SUPPORTED_ABIS, help="目标 ABI, 默认 arm64")
    parser.add_argument("--image", default=None, help="本地镜像名, 默认按输入指纹生成")
    parser.add_argument("--registry", default=DEFAULT_REGISTRY,
                        help=f"远端镜像仓库, 默认 {DEFAULT_REGISTRY}")
    parser.add_argument("--no-pull", dest="no_pull", action="store_true",
                        help="不从远端拉取镜像, 只在本地复用或重建")
    parser.add_argument("--rebuild", action="store_true", help="强制在本地重建镜像")
    parser.add_argument("--print-meta", dest="print_meta", action="store_true",
                        help="只打印镜像元信息 JSON, 供 CI 使用")
    parser.add_argument("--shell", action="store_true", help="只进入容器 shell, 不执行构建")
    parser.add_argument("--build-only", dest="build_only", action="store_true",
                        help="只构建镜像, 不运行容器")
    parser.add_argument("--secrets", default=None,
                        help="签名密钥目录, 默认 <项目根>/secrets, worktree 里回退到主工作树的 secrets")
    args = parser.parse_args(own_args)
    mode = args.mode or "release"

    version = flutter_version()
    patch_hash = patch_set_hash()
    input_hash = build_input_hash()
    image_tag = image_reference(version, patch_hash, input_hash)
    image = args.image or f"piliplus-android-builder:{image_tag}"
    remote_image = f"{args.registry}:{image_tag}"

    if args.print_meta:
        print(
            json.dumps(
                {
                    "flutter_version": version,
                    "patch_hash": patch_hash,
                    "build_input_hash": input_hash,
                    "tag": image_tag,
                    "local_image": image,
                    "remote_image": remote_image,
                },
                ensure_ascii=False,
            )
        )
        return

    if shutil.which(MAIN_ENGINE) is None:
        die("找不到 docker 命令, 请先安装并启动 Docker")

    out_dir = ROOT / ".tmp" / "docker-out"
    cache_dir = ROOT / ".tmp" / "docker-cache"
    work_dir = cache_dir / "work"
    # .android 里是 debug keystore, 持久化后每次构建的签名保持一致.
    android_home = cache_dir / "android-home"
    for directory in (out_dir, cache_dir / "gradle", cache_dir / "pub", work_dir, android_home):
        directory.mkdir(parents=True, exist_ok=True)

    need_build = True
    if args.rebuild:
        log("--rebuild 指定, 在本地重建镜像")
    elif image_matches(image, patch_hash, input_hash):
        log(f"复用本地镜像 {image}")
        need_build = False
    elif args.no_pull:
        log("--no-pull 指定, 跳过远端镜像")
    elif not remote_exists(remote_image):
        log(f"远端没有 {remote_image}, 改为本地构建")
    elif pull_remote(remote_image, image) and image_matches(image, patch_hash, input_hash):
        log(f"使用远端镜像 {remote_image}")
        need_build = False
    else:
        log("远端镜像不可用, 改为本地构建")

    if need_build:
        log(f"构建镜像 {image} (Flutter {version}, 补丁 {patch_hash})")
        build_command = [
            MAIN_ENGINE,
            "build",
            "-f",
            str(DOCKERFILE),
            "-t",
            image,
            "--build-arg",
            f"FLUTTER_VERSION={version}",
            "--build-arg",
            f"PATCH_HASH={patch_hash}",
            "--build-arg",
            f"BUILD_INPUT_HASH={input_hash}",
        ]
        for key in ("FLUTTER_STORAGE_BASE_URL", "PUB_HOSTED_URL"):
            value = os.environ.get(key, "")
            if value:
                build_command += ["--build-arg", f"{key}={value}"]
        build_command.append(str(ROOT))
        run(build_command, env=os.environ.copy())

    if args.build_only:
        return

    mounts = [
        "-v",
        f"{ROOT}:/src:ro",
        "-v",
        f"{out_dir}:/out",
        "-v",
        f"{cache_dir / 'gradle'}:/home/ubuntu/.gradle",
        "-v",
        f"{cache_dir / 'pub'}:/home/ubuntu/.pub-cache",
        "-v",
        f"{android_home}:/home/ubuntu/.android",
        "-v",
        f"{work_dir}:/work",
    ]

    secrets_dir = resolve_secrets(args.secrets)
    if secrets_dir is None:
        log("未找到签名密钥目录, 构建会使用 debug 签名")
    else:
        log(f"签名密钥目录: {secrets_dir}")
        mounts += ["-v", f"{secrets_dir}:/secrets:ro"]

    if args.shell:
        run([MAIN_ENGINE, "run", "--rm", "-it", *mounts, image, "bash"])
        return

    log(f"模式 {mode}, ABI {args.abi}, 输出目录 {out_dir}")
    started = time.monotonic()
    container_command = [MAIN_ENGINE, "run", "--rm", *mounts, "-e", "OUT=/out"]
    if secrets_dir is not None:
        container_command += ["-e", "SECRETS_SRC=/secrets"]
    if os.environ.get("FLUTTER_STORAGE_BASE_URL"):
        container_command += ["-e", "FLUTTER_STORAGE_BASE_URL"]
    if os.environ.get("PUB_HOSTED_URL"):
        container_command += ["-e", "PUB_HOSTED_URL"]
    container_command += ["-e", "SRC=/src", image, "android-build", f"--{mode}"]
    if args.dev:
        container_command.append("--dev")
    container_command += ["--abi", args.abi]
    if extra_args:
        container_command += ["--", *extra_args]
    run(container_command, env=os.environ.copy())

    apks = sorted(out_dir.glob("*.apk"))
    if not apks:
        die(f"构建结束但 {out_dir} 下没有 APK")
    log(f"完成, 耗时 {int(time.monotonic() - started)} 秒")
    for apk in apks:
        log(f"产物: {apk} ({apk.stat().st_size / 1024 / 1024:.1f} MiB)")


if __name__ == "__main__":
    main()
