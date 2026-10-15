# =====================================================================
# Сборка одного exe с игрой «Куратор музея».
#
# Запуск из корня проекта:  .\scripts\build_exe.ps1
#
# Результат:  dist\MuseumCurator.exe
# Его можно скопировать на учебный стенд как есть: ни Python, ни Docker,
# ни клиент Oracle на том компьютере не нужны.
# =====================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Set-Location (Split-Path -Parent $PSScriptRoot)

$exePath = ".\dist\MuseumCurator.exe"

$python = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    Write-Host "Не найдено виртуальное окружение .venv" -ForegroundColor Red
    Write-Host "Создайте его:  python -m venv .venv"
    Write-Host "и поставьте зависимости:  .\.venv\Scripts\pip.exe install -r requirements.txt"
    exit 1
}

# ---------------------------------------------------------------------
# Windows не даёт перезаписать запущенный exe. Окно игры или оставшееся
# окно с ошибкой держат файл, и сборка падает на PermissionError уже
# в самом конце. Проверяем это заранее.
# ---------------------------------------------------------------------
if (Test-Path $exePath) {
    try {
        $stream = [System.IO.File]::Open(
            (Resolve-Path $exePath), 'Open', 'ReadWrite', 'None')
        $stream.Close()
    } catch {
        Write-Host ""
        Write-Host "Файл dist\MuseumCurator.exe занят другой программой." -ForegroundColor Red
        Write-Host "Закройте окно игры и окно с сообщением об ошибке, если оно осталось,"
        Write-Host "и запустите сборку снова."
        $running = Get-Process -Name "MuseumCurator" -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host ""
            Write-Host "Сейчас запущено процессов MuseumCurator: $($running.Count)" -ForegroundColor Yellow
            Write-Host "Остановить их можно так:  Stop-Process -Name MuseumCurator"
        }
        exit 1
    }
}

Write-Host "==> Проверяю PyInstaller" -ForegroundColor Cyan
& $python -m PyInstaller --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "    Не установлен, ставлю" -ForegroundColor Yellow
    & $python -m pip install pyinstaller
}

Write-Host "==> Чищу прошлую сборку" -ForegroundColor Cyan
Remove-Item -Recurse -Force build, dist -ErrorAction SilentlyContinue

Write-Host "==> Собираю (это занимает 1-3 минуты)" -ForegroundColor Cyan
$startedAt = Get-Date
& $python -m PyInstaller MuseumCurator.spec --noconfirm
$pyinstallerCode = $LASTEXITCODE

# ---------------------------------------------------------------------
# Разбор предупреждений. PyInstaller перечисляет все ненайденные модули,
# но большинство из них безобидны: это модули только для Linux и macOS
# либо необязательные зависимости. Показываем лишь то, что может
# сломать запуск на Windows.
# ---------------------------------------------------------------------
$warnFile = ".\build\MuseumCurator\warn-MuseumCurator.txt"
if (Test-Path $warnFile) {
    # Заведомо безобидные: POSIX-специфичные и необязательные.
    $harmless = @(
        "pwd", "grp", "termios", "fcntl", "posix", "resource", "readline",
        "_posixsubprocess", "vms_lib", "java", "org", "OpenGL", "bcrypt",
        "collections.abc", "_frozen_importlib"
    )
    $missing = @()
    foreach ($line in (Get-Content $warnFile -Encoding UTF8)) {
        if ($line -match "missing module named '?([A-Za-z0-9_\.]+)'?") {
            $name = $matches[1]
            $root = $name.Split(".")[0]
            # Имя вида oracledb.__name__ — артефакт анализатора, не модуль.
            if ($name -like "*.__name__" -or $name -like "*.__file__") { continue }
            if ($harmless -contains $name -or $harmless -contains $root) { continue }
            $missing += $name
        }
    }
    $missing = $missing | Sort-Object -Unique
    if ($missing) {
        Write-Host ""
        Write-Host "Ненайденные модули (обычно безобидно, но запомните список):" -ForegroundColor Yellow
        $missing | Select-Object -First 15 | ForEach-Object { Write-Host "    $_" }
        Write-Host "    Полный разбор: $warnFile"
    }
}

# ---------------------------------------------------------------------
# Успех засчитываем, только если PyInstaller вернул 0 И файл появился
# заново. Иначе легко принять старый exe за свежесобранный.
# ---------------------------------------------------------------------
Write-Host ""
if ($pyinstallerCode -ne 0) {
    Write-Host "Сборка не удалась: PyInstaller завершился с кодом $pyinstallerCode" -ForegroundColor Red
    Write-Host "Смотрите traceback выше."
    exit 1
}
if (-not (Test-Path $exePath)) {
    Write-Host "Сборка не удалась: файл dist\MuseumCurator.exe не появился." -ForegroundColor Red
    exit 1
}
$built = Get-Item $exePath
if ($built.LastWriteTime -lt $startedAt) {
    Write-Host "Это старый exe от $($built.LastWriteTime) — новый собрать не получилось." -ForegroundColor Red
    exit 1
}

$size = [math]::Round($built.Length / 1MB, 1)
Write-Host "Готово: dist\MuseumCurator.exe ($size МБ, собран $($built.LastWriteTime))" -ForegroundColor Green
Write-Host "Копируйте этот один файл на любой компьютер с Windows."
