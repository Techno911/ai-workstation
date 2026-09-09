#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() {
  printf '\n==> %s\n' "$1"
}

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Этот скрипт должен выполняться внутри Ubuntu/WSL." >&2
  exit 1
fi

step "Системные зависимости"
if [[ "${SKIP_SYSTEM_DEPS:-0}" != "1" ]]; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git build-essential
else
  echo "Системные зависимости уже установлены из Windows."
fi

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  step "Устанавливаю nvm из закреплённого релиза"
  git clone --depth 1 --branch v0.40.3 https://github.com/nvm-sh/nvm.git "$NVM_DIR"
fi

# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
step "Node.js 22"
nvm install 22
nvm alias default 22
nvm use 22

step "bb, Claude Code и Codex"
packages=()
if ! command -v bb >/dev/null 2>&1 || ! command -v bb-app >/dev/null 2>&1; then
  packages+=("bb-app@0.42.1")
else
  echo "Существующая установка bb сохранена: $(bb --version)"
fi
if ! command -v claude >/dev/null 2>&1; then
  packages+=("@anthropic-ai/claude-code@2.1.266")
else
  echo "Существующая установка Claude Code сохранена: $(claude --version)"
fi
if ! command -v codex >/dev/null 2>&1; then
  packages+=("@openai/codex@0.153.4")
else
  echo "Существующая установка Codex сохранена: $(codex --version)"
fi
if ((${#packages[@]})); then
  npm install --global "${packages[@]}"
fi

step "Постоянные правила и контекст"
mkdir -p "$HOME/.bb/context" "$HOME/.bb/project-template/.bb" "$HOME/.agents/skills"
if [[ -f "$HOME/.bb/AGENTS.md" ]]; then
  echo "Существующий ~/.bb/AGENTS.md сохранён без изменений."
else
  install -m 0644 "$repo_dir/starter/AGENTS.md" "$HOME/.bb/AGENTS.md"
fi
if [[ -f "$HOME/.bb/context/USER_PROFILE.md" ]]; then
  echo "Существующий USER_PROFILE.md сохранён без изменений."
else
  install -m 0644 "$repo_dir/starter/context/USER_PROFILE.md" "$HOME/.bb/context/USER_PROFILE.md"
fi
if [[ -f "$HOME/.bb/context/WORKSPACE_MAP.md" ]]; then
  echo "Существующий WORKSPACE_MAP.md сохранён без изменений."
else
  install -m 0644 "$repo_dir/starter/context/WORKSPACE_MAP.md" "$HOME/.bb/context/WORKSPACE_MAP.md"
fi
if [[ -f "$HOME/.bb/context/INTEGRATIONS_STATUS.md" ]]; then
  echo "Существующий INTEGRATIONS_STATUS.md сохранён без изменений."
else
  install -m 0644 "$repo_dir/starter/context/INTEGRATIONS_STATUS.md" "$HOME/.bb/context/INTEGRATIONS_STATUS.md"
fi
if [[ ! -f "$HOME/.bb/context/FIRST_RUN.md" ]]; then
  install -m 0644 "$repo_dir/starter/FIRST_RUN.md" "$HOME/.bb/context/FIRST_RUN.md"
fi
if [[ ! -f "$HOME/.bb/project-template/.bb/AGENTS.md" ]]; then
  install -m 0644 "$repo_dir/starter/project-template/.bb/AGENTS.md" "$HOME/.bb/project-template/.bb/AGENTS.md"
fi
if [[ ! -f "$HOME/.bb/project-template/PROJECT_CONTEXT.md" ]]; then
  install -m 0644 "$repo_dir/starter/project-template/PROJECT_CONTEXT.md" "$HOME/.bb/project-template/PROJECT_CONTEXT.md"
fi

for skill_dir in "$repo_dir"/starter/skills/*; do
  skill_name="$(basename "$skill_dir")"
  if [[ -e "$HOME/.agents/skills/$skill_name" ]]; then
    mv "$HOME/.agents/skills/$skill_name" "$HOME/.agents/skills/${skill_name}.backup-$(date +%Y%m%d-%H%M%S)"
  fi
  cp -R "$skill_dir" "$HOME/.agents/skills/$skill_name"
done

step "Проверяю команды"
node --version
npm --version
bb --version
claude --version
codex --version

step "Запускаю bb и включаю общую память"
bb-app start
for _ in {1..30}; do
  if bb status >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
bb status >/dev/null
bb plugin enable memory --json >/dev/null

cat <<'EOF'

WSL_READY
Остался вход в подписку:
  claude auth login
или:
  codex login

bb уже запущен. Открыть в Windows: http://localhost:38886
Первый запуск агента: ~/.bb/context/FIRST_RUN.md
EOF
