$targetFile = "$PWD\forge_installer.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: Bulletproof Full-Clean Installer & Launcher
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/7] Cleaning up existing processes & directory ===" -ForegroundColor Cyan
Get-Process -Name "python", "cmd" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Path -like "*SD_Forge*" } | 
    Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path $InstallDir) {
    Write-Host "Removing existing SD_Forge directory to guarantee a clean slate..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Write-Host "[OK] Clean environment ready." -ForegroundColor Green

Write-Host "`n=== [2/7] Verifying Git & uv ===" -ForegroundColor Cyan
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
Write-Host "[OK] Git and uv verified." -ForegroundColor Green

Write-Host "`n=== [3/7] Cloning Forge Repository ===" -ForegroundColor Cyan
git clone $ForgeRepo $InstallDir
Set-Location $InstallDir

Write-Host "`n=== [4/7] Creating Python 3.10 Virtual Environment ===" -ForegroundColor Cyan
$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
& $uv venv $VenvDir --python 3.10 --seed

Write-Host "`n=== [5/7] Installing Dependencies in Advance ===" -ForegroundColor Cyan

# 1. PyTorch (CUDA 12.4)
Write-Host "-> [1/4] Installing PyTorch (CUDA 12.4)..." -ForegroundColor Yellow
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# 2. Forge公式要件の一括インストール
Write-Host "-> [2/4] Installing Forge requirements_versions.txt..." -ForegroundColor Yellow
& $PythonExe -m pip install -r requirements_versions.txt

# 3. 組み込み拡張機能やサブモジュールが裏で要求するパッケージを先回り導入
Write-Host "-> [3/4] Pre-installing CLIP, bitsandbytes, and preprocessor packages..." -ForegroundColor Yellow
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3
& $PythonExe -m pip install fvcore mediapipe onnxruntime svglib insightface handrefinerportable depth_anything depth_anything_v2

# 4. 【最終ロック】すべての依存関係解決後に NumPy 1.x と Pydantic 1.x をピンポイント強制固定
Write-Host "-> [4/4] Pinning NumPy 1.26.4 & Pydantic 1.10.15 (--no-deps)..." -ForegroundColor Yellow
& $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
& $PythonExe -m pip install --force-reinstall --no-deps "pydantic==1.10.15"
& $PythonExe -m pip install --force-reinstall --no-deps scikit-image

Write-Host "`n=== [6/7] Pre-flight Environment Health Check ===" -ForegroundColor Cyan
$healthCheckCode = @"
import numpy as np
import pydantic
from skimage import exposure
import fastapi
import gradio

assert np.__version__.startswith('1.'), f'NumPy must be 1.x, found {np.__version__}'
assert pydantic.__version__.startswith('1.'), f'Pydantic must be 1.x, found {pydantic.__version__}'
print(f'[HealthCheck OK] NumPy: {np.__version__}, Pydantic: {pydantic.__version__}, skimage/FastAPI/Gradio OK')
"@
& $PythonExe -c $healthCheckCode

Write-Host "`n=== [7/7] Configuring Permanent Startup Flags & Launching ===" -ForegroundColor Cyan

# webui-user.bat に --skip-install を設定し、Forge起動時の勝手なpip実行を完全停止
$UserBat = "$InstallDir\webui-user.bat"
@"
@echo off
set PYTHON=%~dp0venv\Scripts\python.exe
set GIT=
set VENV_DIR=%~dp0venv
set COMMANDLINE_ARGS=--cuda-malloc --skip-install

call webui.bat
"@ | Set-Content -Path $UserBat -Encoding Ascii

Write-Host "webui-user.bat configured with: --cuda-malloc --skip-install" -ForegroundColor Green
Write-Host "`nStarting Stable Diffusion WebUI Forge..." -ForegroundColor Green
Write-Host "Access URL: http://127.0.0.1:7860 (Wait until startup completes)" -ForegroundColor Green

cmd.exe /c "webui-user.bat"
'@ | Set-Content -Path $targetFile -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile