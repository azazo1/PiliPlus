[private]
default:
    @just --list --list-submodules

mod build
mod check
mod device
mod generate

# 检查上游更新.
fetch:
    git fetch
    git fetch upstream
