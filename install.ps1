<#
  Установка плагина dsh-deepseek-usage-ru (русская сборка панели расхода DeepSeek).
  Кладёт пакет в профиль DSH, прописывает в зависимости и бандлы.
  С ключом -ReplaceStore убирает магазинную версию deepseek-usage,
  чтобы не было двух панелей и конфликта маршрутов.

  Работает в двух раскладках: когда рядом лежит папка package\ (комплект для переноса)
  и когда файлы плагина лежат в корне репозитория (клон с GitHub).

  Запуск: powershell -ExecutionPolicy Bypass -File .\install.ps1 [-ReplaceStore] [-KeepStore] [-DryRun] [-Profile desktop]
#>
param(
  [switch]$ReplaceStore,
  [switch]$KeepStore,
  [switch]$DryRun,
  [string]$Profile = "desktop"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $here "package"
if (-not (Test-Path (Join-Path $source "package.json"))) { $source = $here }
$manifestSource = Join-Path $source "package.json"

if (-not (Test-Path $manifestSource)) { Write-Host "Нет package.json рядом со скриптом" -ForegroundColor Red; exit 1 }
$meta = Get-Content $manifestSource -Raw -Encoding UTF8 | ConvertFrom-Json
$package = $meta.name
$version = $meta.version

$profileDir = Join-Path $env:USERPROFILE (".dsh\profiles\" + $Profile)
if (-not (Test-Path $profileDir)) {
  Write-Host "Профиль DSH не найден: $profileDir" -ForegroundColor Red
  Write-Host "Запустите DeepSeek Harness один раз, затем повторите."
  exit 1
}

$manifestPath = Join-Path $profileDir "package.json"
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bundles = @()
if ($manifest.dsh.profile.bundles) { $bundles = @($manifest.dsh.profile.bundles) }

$target = Join-Path $profileDir ("node_modules\" + $package)

if ($ReplaceStore) {
  $oldDir = Join-Path $profileDir "node_modules\deepseek-usage"
  if (Test-Path $oldDir) {
    if ($KeepStore) {
      $aside = $oldDir + ".disabled-" + (Get-Date -Format "yyyyMMdd-HHmmss")
      Write-Host "отключаю магазинную версию (файлы сохраняются): $aside"
      if (-not $DryRun) {
        Move-Item $oldDir $aside
        $asideMeta = Join-Path $aside "package.json"
        if (Test-Path $asideMeta) { Copy-Item $asideMeta (Join-Path $here ("deepseek-usage-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")) -Force }
        New-Item -ItemType File -Path (Join-Path $aside "DISABLED.txt") -Force | Out-Null
        Set-Content -Path (Join-Path $aside "DISABLED.txt") -Value "Отключено при переходе на dsh-deepseek-usage-ru. Файлы сохранены, плагин не загружается." -Encoding UTF8
      }
    } else {
      Write-Host "удаляю магазинную версию: $oldDir"
      if (-not $DryRun) { Remove-Item $oldDir -Recurse -Force }
    }
  }
  if ($bundles -contains "deepseek-usage") {
    Write-Host "убираю deepseek-usage из бандлов"
    $bundles = @($bundles | Where-Object { $_ -ne "deepseek-usage" })
  }
  if ($null -ne $manifest.dependencies.'deepseek-usage') {
    Write-Host "убираю deepseek-usage из зависимостей"
    $manifest.dependencies.PSObject.Properties.Remove("deepseek-usage")
  }
}

$addBundle = $bundles -notcontains $package
if ($addBundle) { Write-Host "бандлы: добавлен $package" }

if (Test-Path $target) {
  $backup = $target + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
  Write-Host "текущая версия сохраняется: $backup"
  if (-not $DryRun) { Copy-Item $target $backup -Recurse -Force; Remove-Item $target -Recurse -Force }
}

# Копируем только содержимое пакета: служебные файлы репозитория (index.json, .git, сам скрипт) в профиль не нужны.
$payload = @("package.json", "cordis.patch.yml", "icon.svg", "LICENSE", "README.md", "NOTICE.md") +
  @("src", "locale") | Where-Object { Test-Path (Join-Path $source $_) }

Write-Host "копирование: $source -> $target"
if (-not $DryRun) {
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  foreach ($item in $payload) { Copy-Item (Join-Path $source $item) $target -Recurse -Force }
}

if ($addBundle -or $ReplaceStore -or $null -eq $manifest.dependencies.$package) {
  if ($addBundle) { $manifest.dsh.profile.bundles = @($bundles) + $package }
  if ($null -eq $manifest.dependencies.$package) {
    $manifest.dependencies | Add-Member -NotePropertyName $package -NotePropertyValue $version -Force
  }
  Write-Host "запись $manifestPath"
  if (-not $DryRun) {
    # ВАЖНО: без BOM. PowerShell 5.1 с -Encoding UTF8 пишет BOM, а DSH читает манифест
    # как JSON и падает на первом байте (проверено 22.11.2026).
    $json = $manifest | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    $check = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $check.dsh.profile.bundles) { throw "манифест записан некорректно" }
    Write-Host "манифест проверен: JSON валиден, без BOM"
  }
}

Write-Host ""
if ($DryRun) { Write-Host "Пробный прогон: ничего не изменено." }
else { Write-Host "Готово. Полностью перезапустите DeepSeek Harness." -ForegroundColor Green }
