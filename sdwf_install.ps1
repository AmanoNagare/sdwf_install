$targetFile = "$PWD\forge_installer.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: Self-Healing Installer & Launcher
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/6] Checking Git & uv ===" -ForegroundColor Cyan
if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "Git is not installed or not in PATH."
    exit 1
}

$uvExe = "$HOME\.local\bin\uv.exe"
if (Get-Command "uv" -ErrorAction SilentlyContinue) {
    $uv = "uv"
} elseif (Test-Path $uvExe) {
    $uv = $uvExe
} else {
    Write-Host "Installing uv..." -ForegroundColor Yellow
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $uv = $uvExe
}
$env:Path = "$HOME\.local\bin;$env:Path"

Write-Host "`n=== [2/6] Syncing Repository ===" -ForegroundColor Cyan
if (-not (Test-Path $InstallDir)) {
    git clone $ForgeRepo $InstallDir
}
Set-Location $InstallDir

Write-Host "`n=== [3/6] Setting Up Python venv ===" -ForegroundColor Cyan
$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    & $uv venv $VenvDir --python 3.10 --seed
}

Write-Host "`n=== [4/6] Creating Safety Constraints & Fixing webui-user.bat ===" -ForegroundColor Cyan

# 1. Forgeの裏側pipが絶対にNumPy 2.xを入れないよう制約ファイルを作成
$ConstraintFile = "$InstallDir\constraints.txt"
@"
numpy>=1.26.2,<2.0.0
setuptools<70
"@ | Set-Content -Path $ConstraintFile -Encoding Ascii

# 環境変数に制約を注入（すべてのサブプロセスに継承）
$env:PIP_CONSTRAINT = $ConstraintFile

# 2. webui-user.bat を直接書き換え（引数とPythonパスを確実に固定）
$UserBat = "$InstallDir\webui-user.bat"
@"
@echo off
set PYTHON=%~dp0venv\Scripts\python.exe
set GIT=
set VENV_DIR=%~dp0venv
set COMMANDLINE_ARGS=--cuda-malloc
set PIP_CONSTRAINT=%~dp0constraints.txt

call webui.bat
"@ | Set-Content -Path $UserBat -Encoding Ascii
Write-Host "[OK] Configured webui-user.bat with --cuda-malloc & constraints." -ForegroundColor Green

Write-Host "`n=== [5/6] Pre-installing Key Dependencies ===" -ForegroundColor Cyan
# PyTorch (CUDA 12.4)
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# Forge本体の依存関係
if (Test-Path "requirements_versions.txt") {
    & $uv pip install -r requirements_versions.txt --python $PythonExe
}

# 先回りインストール（CLIP & bitsandbytes）
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3

# --- リカバリー関数定義 ---
function Repair-Environment {
    Write-Host "[Safety Recovery] Re-aligning NumPy 1.26 and scikit-image binaries..." -ForegroundColor Yellow
    & $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
    & $PythonExe -m pip install --force-reinstall scikit-image
}

function Test-EnvironmentHealth {
    $code = "import numpy; assert numpy.__version__.startswith('1.'); from skimage import exposure; print('HEALTH_OK')"
    $test = & $PythonExe -c $code 2>&1
    return ($test -like "*HEALTH_OK*")
}

# 初回整合性合わせ
if (-not (Test-EnvironmentHealth)) {
    Repair-Environment
}

Write-Host "`n=== [6/6] Launching Stable Diffusion WebUI Forge with Auto-Recovery ===" -ForegroundColor Cyan

$maxRetries = 2
$attempt = 0

while ($attempt -le $maxRetries) {
    $attempt++
    Write-Host "`n[Launch Attempt $attempt] Starting Forge..." -ForegroundColor Green
    Write-Host "URL: http://127.0.0.1:7860 (Wait until startup completes)" -ForegroundColor Green

    # Forge起動
    cmd.exe /c "webui-user.bat"
    $exitCode = $LASTEXITCODE

    # 正常終了（ユーザーがCtrl+Cで閉じた等）ならループ終了
    if ($exitCode -eq 0) {
        Write-Host "Forge terminated normally." -ForegroundColor Cyan
        break
    }

    # 異常終了した場合のヘルスチェック
    Write-Warning "Forge exited with code $exitCode. Checking environment health..."
    if (-not (Test-EnvironmentHealth)) {
        Write-Warning "[Alert] NumPy/skimage binary mismatch detected!"
        Repair-Environment
        Write-Host "Environment repaired. Restarting Forge automatically..." -ForegroundColor Green
    } else {
        Write-Warning "Environment binary check passed. Error was likely caused by something else."
        break
    }
}
'@ | Set-Content -Path $targetFile -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile