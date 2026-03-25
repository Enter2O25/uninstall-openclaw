#!/usr/bin/env bash

set -euo pipefail

readonly REMOTE_BASE_URL="${OPENCLAW_REMOTE_BASE_URL:-https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main}"

TEMP_DIR=""

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

show_usage() {
  cat <<'EOF'
用法:
  curl -fsSL https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/uninstall.sh | bash
  curl -fsSL https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main/uninstall.sh | bash -s -- --mode full --yes

支持参数:
  --mode full|app
  --yes
  --dry-run
EOF
}

# 中文注释：退出时统一清理临时目录，避免远程一键执行后在机器上残留中间文件。
cleanup() {
  local exit_code=$?

  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi

  exit "$exit_code"
}

# 中文注释：兼容 Linux 与 macOS 的 mktemp 差异，保证远程脚本在常见服务器环境可直接运行。
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

# 中文注释：统一下载入口，优先 curl，其次 wget，避免不同服务器环境下命令不一致。
download_file() {
  local file_name="$1"
  local target_path="$2"
  local file_url="${REMOTE_BASE_URL%/}/${file_name}"

  if command_exists curl; then
    curl -fsSL "$file_url" -o "$target_path"
    return 0
  fi

  if command_exists wget; then
    wget -qO "$target_path" "$file_url"
    return 0
  fi

  log_error "未找到 curl 或 wget，无法下载远程脚本。"
  return 1
}

# 中文注释：这里显式识别 Git Bash / MSYS / Cygwin，才能在 Windows 的 bash 环境里切到 PowerShell 卸载逻辑。
detect_platform() {
  local uname_value=""

  uname_value="$(uname -s 2>/dev/null || true)"

  case "$uname_value" in
    Linux*) printf 'linux\n' ;;
    Darwin*) printf 'macos\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows\n' ;;
    *)
      log_error "暂不支持当前环境：${uname_value:-unknown}"
      return 1
      ;;
  esac
}

# 中文注释：统一入口接受 bash 风格参数，切到 PowerShell 时在这里做最小必要的参数翻译。
build_windows_args() {
  local args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode|-Mode)
        [[ $# -lt 2 ]] && {
          log_error "$1 需要一个参数"
          return 1
        }
        args+=("-Mode" "$2")
        shift 2
        ;;
      --yes|-Yes)
        args+=("-Yes")
        shift
        ;;
      --dry-run|-DryRun)
        args+=("-DryRun")
        shift
        ;;
      --help|-h|-Help)
        show_usage
        exit 0
        ;;
      *)
        log_error "不支持的参数：$1"
        return 1
        ;;
    esac
  done

  printf '%s\n' "${args[@]}"
}

run_unix_uninstall() {
  local target_script="$1"
  shift

  chmod +x "$target_script"
  bash "$target_script" "$@"
}

run_windows_uninstall() {
  local target_script="$1"
  shift
  local ps_bin=""
  local -a ps_args=()
  local arg=""

  if command_exists powershell.exe; then
    ps_bin="powershell.exe"
  elif command_exists pwsh.exe; then
    ps_bin="pwsh.exe"
  elif command_exists pwsh; then
    ps_bin="pwsh"
  else
    log_error "未找到 powershell.exe 或 pwsh，无法执行 Windows 卸载。"
    return 1
  fi

  while IFS= read -r arg; do
    [[ -n "$arg" ]] && ps_args+=("$arg")
  done < <(build_windows_args "$@")

  "$ps_bin" -NoProfile -ExecutionPolicy Bypass -File "$target_script" "${ps_args[@]}"
}

main() {
  local platform=""
  local target_name=""
  local target_script=""

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
  fi

  platform="$(detect_platform)"
  TEMP_DIR="$(create_temp_dir)"

  case "$platform" in
    linux|macos)
      target_name="uninstall-openclaw.sh"
      target_script="$TEMP_DIR/$target_name"
      download_file "$target_name" "$target_script"
      run_unix_uninstall "$target_script" "$@"
      ;;
    windows)
      target_name="uninstall-openclaw.ps1"
      target_script="$TEMP_DIR/$target_name"
      download_file "$target_name" "$target_script"
      run_windows_uninstall "$target_script" "$@"
      ;;
  esac
}

trap cleanup EXIT

main "$@"
