[CmdletBinding()]
param(
    [switch]$SkipWsl,
    [switch]$SkipModel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)] [object]$Object,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] $Value
    )
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = "$Path.backup-$stamp"
        Copy-Item -LiteralPath $Path -Destination $backup
        Write-Host "Backup: $backup"
    }
}

if ($env:OS -ne "Windows_NT") {
    throw "Этот скрипт предназначен для Windows."
}

Write-Step "Проверяю winget"
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw "winget не найден. Обновите 'Установщик приложений' в Microsoft Store и повторите запуск."
}

Write-Step "Устанавливаю Handy"
$wingetList = (& winget.exe list --id cjpais.Handy -e --accept-source-agreements 2>$null | Out-String)
$handyInstalled = ($LASTEXITCODE -eq 0) -and ($wingetList -match "cjpais\.Handy")
if (-not $handyInstalled) {
    & winget.exe install --id cjpais.Handy -e --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "winget не смог установить Handy, код $LASTEXITCODE"
    }
} else {
    Write-Host "Handy уже установлен."
}

$handyData = Join-Path $env:APPDATA "handy"
$modelsDir = Join-Path $handyData "models"
$settingsPath = Join-Path $handyData "settings_store.json"
New-Item -ItemType Directory -Force -Path $modelsDir | Out-Null

$modelName = "whisper-large-v3-turbo-Q8_0.gguf"
$modelPath = Join-Path $modelsDir $modelName
$partialPath = "$modelPath.partial"
$modelUrl = "https://huggingface.co/handy-computer/whisper-large-v3-turbo-gguf/resolve/5eaf945c7978e564bae5b28a5b1639dd93c2bfb1/whisper-large-v3-turbo-Q8_0.gguf"
$modelSha256 = "b2e30cc286bc9f3aba4db9099fc7403543497c05ce7100d0d83091ddfd25a183"
$modelSize = 886381760

if (-not $SkipModel) {
    $validModel = $false
    if (Test-Path -LiteralPath $modelPath) {
        $existingHash = (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $validModel = $existingHash -eq $modelSha256
    }

    if (-not $validModel) {
        if (Test-Path -LiteralPath $partialPath) {
            $partialFile = Get-Item -LiteralPath $partialPath
            if ($partialFile.Length -ge $modelSize) {
                $partialHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if (($partialFile.Length -eq $modelSize) -and ($partialHash -eq $modelSha256)) {
                    Move-Item -LiteralPath $partialPath -Destination $modelPath -Force
                    $validModel = $true
                } else {
                    $badPartial = "$partialPath.bad-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    Move-Item -LiteralPath $partialPath -Destination $badPartial
                    Write-Warning "Некорректная предыдущая загрузка отложена в $badPartial"
                }
            }
        }
    }

    if (-not $validModel) {
        Write-Step "Скачиваю Whisper Large v3 Turbo (загрузка продолжится после обрыва)"
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
            throw "curl.exe не найден в Windows."
        }
        & curl.exe -L --fail --retry 5 --retry-delay 2 --continue-at - --output $partialPath $modelUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Не удалось скачать модель, код curl $LASTEXITCODE"
        }
        $downloadHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($downloadHash -ne $modelSha256) {
            $badPartial = "$partialPath.bad-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -LiteralPath $partialPath -Destination $badPartial
            Write-Warning "SHA-256 после докачки не совпал. Повреждённый файл отложен в $badPartial. Повторяю загрузку с нуля."
            & curl.exe -L --fail --retry 5 --retry-delay 2 --output $partialPath $modelUrl
            if ($LASTEXITCODE -ne 0) {
                throw "Чистая повторная загрузка модели завершилась с кодом curl $LASTEXITCODE"
            }
            $downloadHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($downloadHash -ne $modelSha256) {
                throw "SHA-256 не совпал и после чистой повторной загрузки. Файл не будет использован."
            }
        }
        Move-Item -LiteralPath $partialPath -Destination $modelPath -Force
    }
}

Write-Step "Применяю проверенный профиль Handy"
$runningHandy = Get-Process -Name "Handy" -ErrorAction SilentlyContinue
$handyRestartPath = $null
if ($runningHandy) {
    Write-Host "На время записи настроек закрываю Handy."
    $handyRestartPath = $runningHandy | Select-Object -First 1 -ExpandProperty Path
    $runningHandy | Stop-Process -Force
}

try {
    Backup-File $settingsPath
    if (Test-Path -LiteralPath $settingsPath) {
        $store = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $store = [pscustomobject]@{}
    }

    if (-not ($store.PSObject.Properties.Name -contains "settings")) {
        $store | Add-Member -MemberType NoteProperty -Name "settings" -Value ([pscustomobject]@{})
    }

    $promptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config\handy-prompt.txt"
    $promptText = (Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8).Trim()
    $settings = $store.settings
    Set-JsonProperty $settings "selected_model" "handy-computer/whisper-large-v3-turbo-gguf/whisper-large-v3-turbo-Q8_0.gguf"
    Set-JsonProperty $settings "onboarding_completed" $true
    Set-JsonProperty $settings "selected_language" "ru"
    Set-JsonProperty $settings "custom_words" ([object[]]@($promptText))
    Set-JsonProperty $settings "vad_enabled" $true
    Set-JsonProperty $settings "post_process_enabled" $false
    Set-JsonProperty $settings "word_correction_threshold" 0.18
    Set-JsonProperty $settings "filler_word_removal_enabled" $true
    Set-JsonProperty $settings "paste_method" "ctrl_v"
    Set-JsonProperty $settings "clipboard_handling" "dont_modify"
    Set-JsonProperty $settings "push_to_talk" $false

    $settingsJson = $store | ConvertTo-Json -Depth 50
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($settingsPath, $settingsJson + [Environment]::NewLine, $utf8NoBom)
} catch {
    throw "Не удалось безопасно обновить settings_store.json. Резервная копия сохранена. Причина: $($_.Exception.Message)"
} finally {
    if ($handyRestartPath -and (Test-Path -LiteralPath $handyRestartPath)) {
        Start-Process -FilePath $handyRestartPath
        Write-Host "Handy снова запущен."
    }
}

if (-not $SkipModel) {
    $finalHash = (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($finalHash -ne $modelSha256) {
    throw "Итоговая проверка модели не пройдена."
    }
}

if ($SkipWsl) {
    Write-Host "`nHandy настроен. WSL пропущен по параметру -SkipWsl." -ForegroundColor Green
    exit 0
}

Write-Step "Проверяю WSL2 и Ubuntu"
$wslDistros = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim([char]0).Trim() } | Where-Object { $_ })
$ubuntuReady = $wslDistros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1

if (-not $ubuntuReady) {
    Write-Host "Ubuntu ещё не установлена. Сейчас Windows включит WSL2." -ForegroundColor Yellow
    & wsl.exe --install -d Ubuntu
    Write-Host "`nНУЖНА ПЕРЕЗАГРУЗКА. После входа откройте Ubuntu, создайте локального пользователя и повторите этот же скрипт." -ForegroundColor Yellow
    exit 3010
}

$repoWindows = Split-Path -Parent $PSScriptRoot
$repoWsl = (& wsl.exe -d $ubuntuReady -- wslpath -a $repoWindows).Trim()
if (-not $repoWsl) {
    throw "Не удалось преобразовать путь репозитория для WSL."
}

Write-Step "Ставлю рабочую среду внутрь $ubuntuReady"
& wsl.exe -d $ubuntuReady -u root -- bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git build-essential"
if ($LASTEXITCODE -ne 0) {
    throw "Не удалось поставить системные пакеты Ubuntu, код $LASTEXITCODE"
}
& wsl.exe -d $ubuntuReady -- bash -lc "cd '$repoWsl' && SKIP_SYSTEM_DEPS=1 bash scripts/setup-wsl.sh"
if ($LASTEXITCODE -ne 0) {
    throw "Установка внутри WSL завершилась с кодом $LASTEXITCODE"
}

Write-Host "`nУстановка завершена. Выполните scripts\verify-windows.ps1" -ForegroundColor Green
