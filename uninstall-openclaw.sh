#!/usr/bin/env bash

set -uo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly OS_NAME="$(uname -s)"

MODE=""
AUTO_YES=false
DRY_RUN=false
ACTIONS=0

CANDIDATE_PATHS=()
ENVIRONMENT_PATHS=()

PACKAGE_NAMES=(
  "openclaw"
  "open-claw"
  "open_claw"
)

PROFILE_FILES=(
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
  "$HOME/.profile"
  "$HOME/.zshrc"
  "$HOME/.zprofile"
)

ENV_VAR_NAMES=(
  "OPENCLAW_HOME"
  "OPENCLAW_CONFIG"
  "OPENCLAW_DATA_DIR"
  "OPENCLAW_CACHE_DIR"
  "OPENCLAW_VENV"
)

# 中文注释：统一日志格式，方便用户快速看懂每一步在做什么。
log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

print_usage() {
  cat <<EOF
用法:
  ./$SCRIPT_NAME [--mode full|app] [--yes] [--dry-run]

参数:
  --mode full    全部卸载清理（包括环境）
  --mode app     保留环境，只卸载清理 OpenClaw
  --yes          跳过确认提示
  --dry-run      只预览将执行的动作，不真正删除
  --help         显示帮助

可选环境变量:
  OPENCLAW_EXTRA_PATHS   额外清理路径，使用冒号分隔
EOF
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 中文注释：把命令渲染成可读字符串，便于 dry-run 时展示实际执行内容。
format_command() {
  local rendered=""
  local arg=""

  for arg in "$@"; do
    if [[ -n "$rendered" ]]; then
      rendered+=" "
    fi
    rendered+="$(printf '%q' "$arg")"
  done

  printf '%s' "$rendered"
}

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[dry-run] $(format_command "$@")"
    return 0
  fi

  "$@"
}

run_root_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      log_info "[dry-run] $(format_command "$@")"
    else
      log_info "[dry-run] sudo $(format_command "$@")"
    fi
    return 0
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return 0
  fi

  if command_exists sudo; then
    sudo "$@"
    return 0
  fi

  log_warn "缺少 sudo，无法执行需要管理员权限的命令：$(format_command "$@")"
  return 1
}

# 中文注释：数组去重，避免同一路径被重复删除或重复展示。
append_unique_path() {
  local path="$1"
  local existing=""

  [[ -z "$path" ]] && return 0

  for existing in "${CANDIDATE_PATHS[@]:-}"; do
    [[ "$existing" == "$path" ]] && return 0
  done

  CANDIDATE_PATHS+=("$path")
}

append_unique_env_path() {
  local path="$1"
  local existing=""

  [[ -z "$path" ]] && return 0

  for existing in "${ENVIRONMENT_PATHS[@]:-}"; do
    [[ "$existing" == "$path" ]] && return 0
  done

  ENVIRONMENT_PATHS+=("$path")
}

add_existing_path() {
  local path="$1"

  if [[ -e "$path" || -L "$path" ]]; then
    append_unique_path "$path"
  fi
}

add_existing_env_path() {
  local path="$1"

  if [[ -e "$path" || -L "$path" ]]; then
    append_unique_env_path "$path"
  fi
}

# 中文注释：命令路径发现后，只在目录名本身明确指向 OpenClaw 时才继续扩展，避免误删公共 bin 目录。
discover_command_paths() {
  local cmd=""
  local cmd_path=""
  local cmd_dir=""
  local parent_dir=""
  local cmd_dir_name=""
  local parent_dir_name=""

  for cmd in "openclaw" "open-claw" "OpenClaw"; do
    if ! cmd_path="$(command -v "$cmd" 2>/dev/null)"; then
      continue
    fi

    add_existing_path "$cmd_path"
    cmd_dir="$(cd "$(dirname "$cmd_path")" 2>/dev/null && pwd -P)"
    add_existing_path "$cmd_dir/$cmd"

    if [[ -n "$cmd_dir" ]]; then
      cmd_dir_name="$(basename "$cmd_dir")"
      if [[ "$cmd_dir_name" =~ [Oo]pen[-_]?Claw || "$cmd_dir_name" =~ [Oo]penclaw ]]; then
        append_unique_path "$cmd_dir"
      fi

      parent_dir="$(cd "$cmd_dir/.." 2>/dev/null && pwd -P || true)"
      if [[ -n "$parent_dir" ]]; then
        parent_dir_name="$(basename "$parent_dir")"
        if [[ "$parent_dir_name" =~ [Oo]pen[-_]?Claw || "$parent_dir_name" =~ [Oo]penclaw ]]; then
          append_unique_path "$parent_dir"
        fi
      fi
    fi
  done
}

load_common_paths() {
  local extra_path=""

  add_existing_path "$HOME/OpenClaw"
  add_existing_path "$HOME/openclaw"
  add_existing_path "$HOME/.openclaw"
  add_existing_path "$HOME/.config/openclaw"
  add_existing_path "$HOME/.cache/openclaw"
  add_existing_path "$HOME/.local/share/openclaw"
  add_existing_path "$HOME/.local/state/openclaw"
  add_existing_path "$HOME/.local/bin/openclaw"
  add_existing_path "/usr/local/bin/openclaw"
  add_existing_path "/usr/bin/openclaw"
  add_existing_path "/opt/homebrew/bin/openclaw"
  add_existing_path "/opt/openclaw"
  add_existing_path "/usr/local/openclaw"
  add_existing_path "/etc/openclaw"
  add_existing_path "/var/lib/openclaw"
  add_existing_path "/var/log/openclaw"
  add_existing_path "/var/log/openclaw.log"

  discover_command_paths

  if [[ -n "${OPENCLAW_EXTRA_PATHS:-}" ]]; then
    IFS=':' read -r -a extra_paths <<< "${OPENCLAW_EXTRA_PATHS}"
    for extra_path in "${extra_paths[@]}"; do
      [[ -n "$extra_path" ]] && append_unique_path "$extra_path"
    done
  fi

  case "$OS_NAME" in
    Darwin)
      add_existing_path "/Applications/OpenClaw.app"
      add_existing_path "$HOME/Applications/OpenClaw.app"
      add_existing_path "$HOME/Library/Application Support/OpenClaw"
      add_existing_path "$HOME/Library/Caches/OpenClaw"
      add_existing_path "$HOME/Library/Logs/OpenClaw"
      add_existing_path "$HOME/Library/Preferences/com.openclaw.plist"
      add_existing_path "$HOME/Library/LaunchAgents/com.openclaw.agent.plist"
      add_existing_path "/Library/Application Support/OpenClaw"
      add_existing_path "/Library/LaunchDaemons/com.openclaw.service.plist"
      ;;
    Linux)
      add_existing_path "$HOME/.config/systemd/user/openclaw.service"
      add_existing_path "$HOME/.local/share/applications/openclaw.desktop"
      add_existing_path "/etc/systemd/system/openclaw.service"
      add_existing_path "/usr/lib/systemd/system/openclaw.service"
      add_existing_path "/usr/share/applications/openclaw.desktop"
      add_existing_path "/var/cache/openclaw"
      ;;
    *)
      log_error "当前系统 $OS_NAME 不在此脚本支持范围内。"
      exit 1
      ;;
  esac
}

# 中文注释：环境清理只删除明显绑定 OpenClaw 的环境目录，避免误删用户的通用运行时。
load_environment_paths() {
  local install_path=""

  add_existing_env_path "$HOME/.virtualenvs/openclaw"
  add_existing_env_path "$HOME/.local/pipx/venvs/openclaw"
  add_existing_env_path "$HOME/miniconda3/envs/openclaw"
  add_existing_env_path "$HOME/anaconda3/envs/openclaw"
  add_existing_env_path "$HOME/.conda/envs/openclaw"

  for install_path in "${CANDIDATE_PATHS[@]:-}"; do
    if [[ -d "$install_path" ]]; then
      add_existing_env_path "$install_path/.venv"
      add_existing_env_path "$install_path/venv"
      add_existing_env_path "$install_path/env"
      add_existing_env_path "$install_path/.python-version"
    fi
  done
}

choose_mode_interactively() {
  local choice=""

  printf '\n请选择卸载模式：\n'
  printf '  1. 全部卸载清理（包括环境）\n'
  printf '  2. 保留环境，只卸载清理 OpenClaw\n'
  printf '请输入选项 [1/2]: '
  read -r choice

  case "$choice" in
    1) MODE="full" ;;
    2) MODE="app" ;;
    *)
      log_error "无效选项：$choice"
      exit 1
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        [[ $# -lt 2 ]] && {
          log_error "--mode 需要一个参数"
          exit 1
        }
        MODE="$2"
        shift 2
        ;;
      --yes)
        AUTO_YES=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        log_error "未知参数：$1"
        print_usage
        exit 1
        ;;
    esac
  done

  if [[ -n "$MODE" && "$MODE" != "full" && "$MODE" != "app" ]]; then
    log_error "--mode 仅支持 full 或 app"
    exit 1
  fi
}

confirm_execution() {
  local mode_label=""
  local answer=""

  [[ "$AUTO_YES" == true ]] && return 0

  if [[ "$MODE" == "full" ]]; then
    mode_label="全部卸载清理（包括环境）"
  else
    mode_label="保留环境，只卸载清理 OpenClaw"
  fi

  printf '\n即将执行：%s\n' "$mode_label"
  printf '确认继续？[y/N]: '
  read -r answer

  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      log_warn "用户已取消。"
      exit 0
      ;;
  esac
}

# 中文注释：先停进程再删文件，避免进程占用导致部分文件残留。
stop_processes() {
  local pattern='openclaw|open-claw|open_claw|OpenClaw'

  if command_exists pgrep && pgrep -f "$pattern" >/dev/null 2>&1; then
    run_cmd pkill -f "$pattern"
    ACTIONS=$((ACTIONS + 1))
  fi
}

cleanup_linux_services() {
  local unit=""
  local units=(
    "openclaw"
    "openclaw.service"
    "open-claw"
  )

  command_exists systemctl || return 0

  for unit in "${units[@]}"; do
    if systemctl status "$unit" >/dev/null 2>&1 || systemctl list-unit-files "$unit" >/dev/null 2>&1; then
      run_root_cmd systemctl stop "$unit" >/dev/null 2>&1 || true
      run_root_cmd systemctl disable "$unit" >/dev/null 2>&1 || true
      ACTIONS=$((ACTIONS + 1))
    fi
  done
}

cleanup_macos_services() {
  local label=""
  local plist=""
  local labels=(
    "com.openclaw.agent"
    "com.openclaw.service"
    "openclaw"
  )
  local plists=(
    "$HOME/Library/LaunchAgents/com.openclaw.agent.plist"
    "/Library/LaunchDaemons/com.openclaw.service.plist"
  )

  command_exists launchctl || return 0

  for label in "${labels[@]}"; do
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || launchctl print "system/$label" >/dev/null 2>&1; then
      run_cmd launchctl remove "$label" >/dev/null 2>&1 || true
      ACTIONS=$((ACTIONS + 1))
    fi
  done

  for plist in "${plists[@]}"; do
    if [[ -f "$plist" ]]; then
      run_cmd launchctl unload "$plist" >/dev/null 2>&1 || true
      ACTIONS=$((ACTIONS + 1))
    fi
  done
}

cleanup_services() {
  case "$OS_NAME" in
    Linux) cleanup_linux_services ;;
    Darwin) cleanup_macos_services ;;
  esac
}

uninstall_brew_packages() {
  local package=""

  command_exists brew || return 0

  for package in "${PACKAGE_NAMES[@]}"; do
    if brew list --formula --versions "$package" >/dev/null 2>&1; then
      run_cmd brew uninstall --formula "$package"
      ACTIONS=$((ACTIONS + 1))
    fi

    if brew list --cask --versions "$package" >/dev/null 2>&1; then
      run_cmd brew uninstall --cask "$package"
      ACTIONS=$((ACTIONS + 1))
    fi
  done
}

uninstall_linux_packages() {
  local package=""

  for package in "${PACKAGE_NAMES[@]}"; do
    if command_exists apt-get && command_exists dpkg && dpkg -s "$package" >/dev/null 2>&1; then
      run_root_cmd apt-get remove -y "$package"
      ACTIONS=$((ACTIONS + 1))
      continue
    fi

    if command_exists dnf && command_exists rpm && rpm -q "$package" >/dev/null 2>&1; then
      run_root_cmd dnf remove -y "$package"
      ACTIONS=$((ACTIONS + 1))
      continue
    fi

    if command_exists yum && command_exists rpm && rpm -q "$package" >/dev/null 2>&1; then
      run_root_cmd yum remove -y "$package"
      ACTIONS=$((ACTIONS + 1))
      continue
    fi

    if command_exists pacman && pacman -Q "$package" >/dev/null 2>&1; then
      run_root_cmd pacman -Rns --noconfirm "$package"
      ACTIONS=$((ACTIONS + 1))
      continue
    fi

    if command_exists snap && snap list "$package" >/dev/null 2>&1; then
      run_root_cmd snap remove "$package"
      ACTIONS=$((ACTIONS + 1))
    fi
  done
}

uninstall_user_level_packages() {
  local package=""

  for package in "${PACKAGE_NAMES[@]}"; do
    if command_exists npm && npm list -g --depth=0 "$package" >/dev/null 2>&1; then
      run_cmd npm uninstall -g "$package"
      ACTIONS=$((ACTIONS + 1))
    fi

    if command_exists pipx && pipx list 2>/dev/null | grep -qiE "(^|[[:space:]])${package}([[:space:]]|$)"; then
      run_cmd pipx uninstall "$package"
      ACTIONS=$((ACTIONS + 1))
    fi
  done
}

remove_conda_env() {
  if [[ "$MODE" != "full" ]]; then
    return 0
  fi

  if command_exists conda && conda env list 2>/dev/null | grep -qiE '(^|[[:space:]])openclaw([[:space:]]|$)'; then
    run_cmd conda env remove -n openclaw -y
    ACTIONS=$((ACTIONS + 1))
  fi
}

uninstall_packages() {
  uninstall_user_level_packages
  remove_conda_env

  case "$OS_NAME" in
    Darwin)
      uninstall_brew_packages
      ;;
    Linux)
      uninstall_linux_packages
      ;;
  esac
}

# 中文注释：这里显式拦住明显危险的目录，避免路径拼装异常时误删根目录或整个用户目录。
remove_path_safely() {
  local target="$1"

  [[ -z "$target" ]] && return 0

  case "$target" in
    "/"|"/bin"|"/sbin"|"/usr"|"/usr/bin"|"/usr/sbin"|"/usr/local"|"/usr/local/bin"|"/opt"|"/opt/homebrew/bin"|"$HOME"|"."|"..")
      log_warn "已跳过危险路径：$target"
      return 0
      ;;
  esac

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[dry-run] 删除 $target"
  else
    rm -rf -- "$target"
  fi
  ACTIONS=$((ACTIONS + 1))
}

remove_candidate_paths() {
  local target=""

  for target in "${CANDIDATE_PATHS[@]:-}"; do
    remove_path_safely "$target"
  done
}

remove_environment_paths() {
  local target=""

  for target in "${ENVIRONMENT_PATHS[@]:-}"; do
    remove_path_safely "$target"
  done
}

# 中文注释：仅删除包含 OpenClaw 关键字的行，避免把用户其它配置误清掉。
clean_profile_file() {
  local file="$1"
  local backup_file=""
  local tmp_file=""

  [[ ! -f "$file" ]] && return 0
  grep -qiE 'openclaw|OPENCLAW_' "$file" || return 0

  if [[ "$DRY_RUN" == true ]]; then
    log_info "[dry-run] 清理配置文件中的 OpenClaw 环境：$file"
    ACTIONS=$((ACTIONS + 1))
    return 0
  fi

  backup_file="${file}.openclaw.bak.$(date +%Y%m%d%H%M%S)"
  tmp_file="${file}.openclaw.tmp"

  cp "$file" "$backup_file"
  grep -viE 'openclaw|OPENCLAW_' "$file" > "$tmp_file" || true
  mv "$tmp_file" "$file"
  ACTIONS=$((ACTIONS + 1))
}

clean_shell_profiles() {
  local file=""

  for file in "${PROFILE_FILES[@]}"; do
    clean_profile_file "$file"
  done
}

print_summary() {
  printf '\n清理完成。\n'
  printf '模式：%s\n' "$([[ "$MODE" == "full" ]] && printf '全部卸载清理（包括环境）' || printf '保留环境，只卸载清理 OpenClaw')"
  printf '执行动作数：%s\n' "$ACTIONS"

  if [[ "$MODE" == "full" ]]; then
    printf '已尝试移除环境变量：%s\n' "${ENV_VAR_NAMES[*]}"
  fi

  printf '\n如果你的 OpenClaw 安装在自定义目录，可通过 OPENCLAW_EXTRA_PATHS 追加路径后重跑。\n'
}

main() {
  parse_args "$@"

  if [[ -z "$MODE" ]]; then
    choose_mode_interactively
  fi

  load_common_paths

  if [[ "$MODE" == "full" ]]; then
    load_environment_paths
  fi

  confirm_execution

  stop_processes
  cleanup_services
  uninstall_packages
  remove_candidate_paths

  if [[ "$MODE" == "full" ]]; then
    remove_environment_paths
    clean_shell_profiles
  fi

  print_summary
}

main "$@"
