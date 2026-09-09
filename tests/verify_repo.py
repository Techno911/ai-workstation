#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

required = [
    "README.md",
    "scripts/setup-windows.ps1",
    "scripts/setup-wsl.sh",
    "scripts/verify-windows.ps1",
    "config/handy-prompt.txt",
    "starter/AGENTS.md",
    "starter/FIRST_RUN.md",
    "starter/context/USER_PROFILE.md",
    "starter/context/WORKSPACE_MAP.md",
    "starter/context/INTEGRATIONS_STATUS.md",
    "starter/project-template/.bb/AGENTS.md",
    "starter/project-template/PROJECT_CONTEXT.md",
    "starter/skills/workstation-facts-before-claim/SKILL.md",
    "starter/skills/workstation-operational-instructions/SKILL.md",
    "starter/skills/workstation-memory/SKILL.md",
    "_qa/transactions.md",
    "_qa/handy-benchmark.md",
    "LICENSE",
]

errors = []
for relative in required:
    if not (ROOT / relative).is_file():
        errors.append(f"missing: {relative}")

texts = {}
for path in ROOT.rglob("*"):
    if path.is_file() and ".git" not in path.parts:
        try:
            texts[path.relative_to(ROOT).as_posix()] = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            pass

joined = "\n".join(texts.values())

# Обобщённые правила: ловят класс данных, не называя конкретных значений.
for pattern, label in [
    (r"gh[opsu]_[A-Za-z0-9_]{20,}", "GitHub token"),
    (r"sk-[A-Za-z0-9_-]{20,}", "API key"),
    (r"/Users/[a-z0-9._-]+", "private macOS path"),
    (r"\b(?:10|100\.6[4-9]|192\.168|172\.(?:1[6-9]|2[0-9]|3[01]))\.\d{1,3}\.\d{1,3}\b", "private network address"),
    (r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "email address"),
    (r"\bt\.me/[A-Za-z0-9_]+", "telegram handle"),
]:
    if re.search(pattern, joined, re.IGNORECASE):
        errors.append(f"forbidden data: {label}")

# Точные строки хранятся хешами: назвать их в открытом виде значит опубликовать их.
FORBIDDEN_HASHES = {
    "3aadded494c910a2d90ce87eb5004c83545e00f2f01ad69138022d36dc9c34bb": "private account",
    "8a8df15e669e46bd14f63866630b801f82639e7d5bd7b0959632cf32064bd395": "personal name of a third party",
    "59f763dc5c26797abd476394e6f8098266d98a9f63655ad5333bbdcee1a01e48": "private server address",
}
words = re.findall(r"[A-Za-zА-Яа-яЁё0-9._@-]+", joined.lower())
seen = set()
for size in (1, 2, 3):
    for i in range(len(words) - size + 1):
        seen.add(hashlib.sha256(" ".join(words[i:i + size]).encode("utf-8")).hexdigest())
for digest, label in FORBIDDEN_HASHES.items():
    if digest in seen:
        errors.append(f"forbidden data: {label}")

setup = texts.get("scripts/setup-windows.ps1", "")
expected_hash = "b2e30cc286bc9f3aba4db9099fc7403543497c05ce7100d0d83091ddfd25a183"
if setup.count(expected_hash) != 1:
    errors.append("setup must contain exactly one model SHA-256")
if "Backup-File $settingsPath" not in setup:
    errors.append("Handy settings backup is not enforced")
if "post_process_enabled\" $false" not in setup:
    errors.append("LLM post-processing is not disabled")
if "Повторяю загрузку с нуля" not in setup or setup.count("$downloadHash -ne $modelSha256") != 2:
    errors.append("corrupt partial download has no clean retry")
for version in ["bb-app@0.42.1", "@anthropic-ai/claude-code@2.1.266", "@openai/codex@0.153.4"]:
    if version not in texts.get("scripts/setup-wsl.sh", ""):
        errors.append(f"dependency is not pinned: {version}")

readme = texts.get("README.md", "")
for marker in ["## Самый короткий вход", "### Главный путь", "### Готово, когда", "### Если что‑то не получилось"]:
    if marker not in readme:
        errors.append(f"README missing route marker: {marker}")

if errors:
    print("\n".join(f"ERROR: {item}" for item in errors))
    sys.exit(1)

print(json.dumps({"ok": True, "files": len(texts)}, ensure_ascii=False))
