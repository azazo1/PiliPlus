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
    parser.add_argument("--image", default=None, help="镜像名, 默认按 Flutter 版本生成")
    parser.add_argument("--rebuild", action="store_true", help="强制重建镜像")
    parser.add_argument("--shell", action="store_true", help="只进入容器 shell, 不执行构建")
    parser.add_argument("--build-only", dest="build_only", action="store_true",
                        help="只构建镜像, 不运行容器")
    args = parser.parse_args(own_args)
    mode = args.mode or "release"

    if shutil.which(MAIN_ENGINE) is None:
        die("找不到 docker 命令, 请先安装并启动 Docker")

    version = flutter_version()
    patch_hash = patch_set_hash()
    input_hash = build_input_hash()
    image = args.image or f"piliplus-android-builder:{version}"

    out_dir = ROOT / ".tmp" / "docker-out"
    cache_dir = ROOT / ".tmp" / "docker-cache"
    work_dir = cache_dir / "work"
    for directory in (out_dir, cache_dir / "gradle", cache_dir / "pub", work_dir):
        directory.mkdir(parents=True, exist_ok=True)

    stale_reason = ""
    if not image_exists(image):
        stale_reason = "镜像缺失"
    elif image_label(image, "piliplus.patch-hash") != patch_hash:
        stale_reason = "lib/scripts 下的补丁已变化"
    elif image_label(image, "piliplus.build-input-hash") != input_hash:
        stale_reason = "Dockerfile 或入口脚本已变化"
    if args.rebuild:
        stale_reason = stale_reason or "指定了 --rebuild"

    if stale_reason:
        log(f"构建镜像 {image} (Flutter {version}, 补丁 {patch_hash}, 原因: {stale_reason})")
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
    else:
        log(f"复用已有镜像 {image} (Flutter {version}, 补丁 {patch_hash}, 镜像输入 {input_hash})")

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
        f"{work_dir}:/work",
    ]

    if args.shell:
        run([MAIN_ENGINE, "run", "--rm", "-it", *mounts, image, "bash"])
        return

    log(f"模式 {mode}, ABI {args.abi}, 输出目录 {out_dir}")
    started = time.monotonic()
    container_command = [MAIN_ENGINE, "run", "--rm", *mounts, "-e", "OUT=/out"]
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
