#!/usr/bin/env bash

set -euo pipefail

readonly REMOTE_BASE_URL="${OPENCLAW_REMOTE_BASE_URL:-https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main}"
readonly TARGET_SCRIPT_NAME="uninstall-openclaw.sh"

TEMP_DIR=""

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 中文注释：退出时统一清理临时目录，避免远程执行后在本机残留中间文件。
cleanup() {
  local exit_code=$?

  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi

  exit "$exit_code"
}

# 中文注释：兼容 Linux 与 macOS 的 mktemp 差异，优先创建专用临时目录。
create_temp_dir() {
  local dir=""

  if dir="$(mktemp -d 2>/dev/null)"; then
    printf '%s\n' "$dir"
    return 0
  fi

  if dir="$(mktemp -d -t openclaw-uninstall 2>/dev/null)"; then
    printf '%s\n' "$dir"
    return 0
  fi

  log_error "创建临时目录失败。"
  return 1
}

# 中文注释：优先使用 curl，其次回退到 wget，保证大部分服务器和桌面环境都能直接运行。
download_remote_script() {
  local target_path="$1"
  local script_url="${REMOTE_BASE_URL%/}/${TARGET_SCRIPT_NAME}"

  if command_exists curl; then
    curl -fsSL "$script_url" -o "$target_path"
    return 0
  fi

  if command_exists wget; then
    wget -qO "$target_path" "$script_url"
    return 0
  fi

  log_error "未找到 curl 或 wget，无法下载远程脚本。"
  return 1
}

# 中文注释：远程入口只负责拉取最新主脚本并原样透传参数，避免维护两套卸载逻辑。
main() {
  local bash_bin=""
  local target_script=""

  bash_bin="$(command -v bash 2>/dev/null || true)"
  if [[ -z "$bash_bin" ]]; then
    log_error "未找到 bash，无法继续执行。"
    exit 1
  fi

  TEMP_DIR="$(create_temp_dir)"
  target_script="$TEMP_DIR/$TARGET_SCRIPT_NAME"

  download_remote_script "$target_script"
  chmod +x "$target_script"
  "$bash_bin" "$target_script" "$@"
}

trap cleanup EXIT

main "$@"
