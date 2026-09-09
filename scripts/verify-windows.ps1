[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    Write-Host "OK: $Message" -ForegroundColor Green
}

Check ($env:OS -eq "Windows_NT") "Windows"
Check ($null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue)) "winget доступен"

$settingsPath = Join-Path $env:APPDATA "handy\settings_store.json"
$modelPath = Join-Path $env:APPDATA "handy\models\whisper-large-v3-turbo-Q8_0.gguf"
$expectedHash = "b2e30cc286bc9f3aba4db9099fc7403543497c05ce7100d0d83091ddfd25a183"

Check (Test-Path -LiteralPath $settingsPath) "настройки Handy созданы"
Check (Test-Path -LiteralPath $modelPath) "модель Handy скачана"
$actualHash = (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant()
Check ($actualHash -eq $expectedHash) "SHA-256 модели совпадает"

$store = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($store.settings.selected_language -eq "ru") "язык Handy: ru"
Check ($store.settings.vad_enabled -eq $true) "VAD включён"
Check ($store.settings.post_process_enabled -eq $false) "LLM-постобработка выключена"
Check ($store.settings.custom_words.Count -eq 1) "подсказка Handy хранится одним прозаическим элементом"
Check ($store.settings.selected_model -eq "handy-computer/whisper-large-v3-turbo-gguf/whisper-large-v3-turbo-Q8_0.gguf") "выбрана Whisper Large v3 Turbo Q8_0"

$distros = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim([char]0).Trim() } | Where-Object { $_ })
$ubuntu = $distros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1
Check ($null -ne $ubuntu) "Ubuntu установлена в WSL"

& wsl.exe -d $ubuntu -- bash -lc "source ~/.nvm/nvm.sh && node --version && bb --version && claude --version && codex --version && bb status >/dev/null && test -f ~/.bb/AGENTS.md && test -f ~/.bb/context/USER_PROFILE.md && test -f ~/.bb/context/INTEGRATIONS_STATUS.md && test -f ~/.bb/context/FIRST_RUN.md && test -f ~/.bb/project-template/PROJECT_CONTEXT.md && test -f ~/.agents/skills/workstation-facts-before-claim/SKILL.md"
Check ($LASTEXITCODE -eq 0) "bb, провайдеры, правила и навыки доступны"

Write-Host "`nREADY" -ForegroundColor Green
