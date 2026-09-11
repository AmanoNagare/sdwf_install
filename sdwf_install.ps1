$targetFile = "$PWD\forge_installer.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: Hardened Installer & Auto-Healing Launcher
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [1/7] Environment Pre-check" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "[Error] Git is not installed or not in PATH."
    exit 1
}
Write-Host "[OK] Git detected: $((Get-Command git).Source)" -ForegroundColor Green

if (Get-Command "nvidia-smi" -ErrorAction SilentlyContinue) {
    Write-Host "[OK] NVIDIA GPU detected (RTX A4000)." -ForegroundColor Green
} else {
    Write-Warning "[Warning] nvidia-smi not found. Forge may run slowly without GPU acceleration."
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [2/7] Locating Package Manager (uv)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$uvExe = "$HOME\.local\bin\uv.exe"
if (Get-Command "uv" -ErrorAction SilentlyContinue) {
    $uv = "uv"
} elseif (Test-Path $uvExe) {
    $uv = $uvExe
} else {
    Write-Host "Installing uv to user profile..." -ForegroundColor Yellow
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $uv = $uvExe
}
$env:Path = "$HOME\.local\bin;$env:Path"
Write-Host "[OK] uv is ready: $uv" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [3/7] Cloning or Verifying Repository" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path "$InstallDir\.git")) {
    if (Test-Path $InstallDir) {
        Write-Warning "Directory exists but .git is missing. Cleaning up for clean clone..."
        Remove-Item -Recurse -Force $InstallDir
    }
    Write-Host "Cloning Forge repository..." -ForegroundColor Yellow
    git clone $ForgeRepo $InstallDir
} else {
    Write-Host "[OK] Forge repository already exists at $InstallDir" -ForegroundColor Green
}
Set-Location $InstallDir

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [4/7] Setting Up Python 3.10 Virtual Environment" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    Write-Host "Creating Python 3.10 venv with pip, wheel, setuptools..." -ForegroundColor Yellow
    & $uv venv $VenvDir --python 3.10 --seed
}
Write-Host "[OK] Python venv ready: $PythonExe" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [5/7] Locking Constraints (pip.ini & constraints.txt)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. 物理制約ファイルの作成（NumPy 2.x, Pydantic 2.x, setuptools 70+ の侵入を阻止）
$ConstraintFile = "$InstallDir\constraints.txt"
@"
numpy>=1.26.2,<2.0.0
pydantic>=1.10.10,<2.0.0
setuptools<70
fastapi<0.100.0
"@ | Set-Content -Path $ConstraintFile -Encoding Ascii

# 2. venv内の pip.ini に制約を恒久設定（Forge内部のどの階層からのpip呼び出しも強制制限）
$PipIni = "$VenvDir\pip.ini"
@"
[global]
constraint = $ConstraintFile
"@ | Set-Content -Path $PipIni -Encoding Ascii

$env:PIP_CONSTRAINT = $ConstraintFile
Write-Host "[OK] Created $ConstraintFile and locked venv pip.ini" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [6/7] Pre-installing Core & Extension Dependencies" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# PyTorch (CUDA 12.4)
Write-Host "-> Installing PyTorch (CUDA 12.4)..." -ForegroundColor Yellow
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# Forge本体の requirements
if (Test-Path "requirements_versions.txt") {
    & $PythonExe -m pip install -r requirements_versions.txt
}

# 競合を起こしやすいビルド済みツールの先行導入
Write-Host "-> Installing CLIP and bitsandbytes..." -ForegroundColor Yellow
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3

# 起動時にForgeが裏で追加しようとしていたControlNet用プリプロセッサ群を先入れ
Write-Host "-> Pre-installing legacy preprocessor requirements..." -ForegroundColor Yellow
& $PythonExe -m pip install fvcore mediapipe onnxruntime svglib insightface handrefinerportable depth_anything depth_anything_v2

# --- 環境の最終修復関数 ---
function Invoke-EnvironmentRepair {
    Write-Host "[Recovery] Re-locking NumPy 1.26, Pydantic 1.10, and scikit-image..." -ForegroundColor Yellow
    & $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4" "pydantic==1.10.19" "fastapi==0.95.2"
    & $PythonExe -m pip install --force-reinstall --no-deps scikit-image
}

# --- 4点整合性ヘルスチェック関数 ---
function Test-ForgeHealth {
    $testScript = @"
import sys
try:
    import numpy, pydantic, fastapi, gradio
    assert numpy.__version__.startswith('1.'), f'NumPy is {numpy.__version__}'
    assert pydantic.__version__.startswith('1.'), f'Pydantic is {pydantic.__version__}'
    from skimage import exposure
    from fastapi.dependencies.utils import get_param_sub_dependant
    print('ALL_HEALTH_CHECKS_PASSED')
except Exception as e:
    print(f'HEALTH_CHECK_FAILED: {e}')
    sys.exit(1)
"@
    $res = & $PythonExe -c $testScript 2>&1
    return ($res -like "*ALL_HEALTH_CHECKS_PASSED*")
}

# 初回チェック＆修復
if (-not (Test-ForgeHealth)) {
    Invoke-EnvironmentRepair
}

# webui-user.bat の書き換え固定
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

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [7/7] Launching WebUI Forge" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (Test-ForgeHealth) {
    Write-Host "[OK] All dependencies verified. Starting Forge..." -ForegroundColor Green
    Write-Host "Access URL: http://127.0.0.1:7860" -ForegroundColor Green
    cmd.exe /c "webui-user.bat"
} else {
    Write-Warning "First health check did not pass cleanly. Applying emergency repair..."
    Invoke-EnvironmentRepair
    cmd.exe /c "webui-user.bat"
}
'@ | Set-Content -Path $targetFile -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile