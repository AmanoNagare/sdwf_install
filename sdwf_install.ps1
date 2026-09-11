$targetFile = "$PWD\forge_installer.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: Final Stable Installer & Launcher
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/6] Cleaning up previous processes & workspace ===" -ForegroundColor Cyan

# 1. 残留プロセスの停止
Get-Process -Name "python", "cmd" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Path -like "*SD_Forge*" } | 
    Stop-Process -Force -ErrorAction SilentlyContinue

# 2. 既存環境の初期化（クリーンな状態からやり直す）
if (Test-Path $InstallDir) {
    Write-Host "Removing existing SD_Forge directory to guarantee clean installation..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Write-Host "[OK] Clean workspace ready." -ForegroundColor Green

Write-Host "`n=== [2/6] Checking Git & uv ===" -ForegroundColor Cyan
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

Write-Host "`n=== [3/6] Cloning Forge Repository ===" -ForegroundColor Cyan
git clone $ForgeRepo $InstallDir
Set-Location $InstallDir

Write-Host "`n=== [4/6] Creating Python 3.10 Virtual Environment ===" -ForegroundColor Cyan
$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
& $uv venv $VenvDir --python 3.10 --seed

Write-Host "`n=== [5/6] Complete Dependency Setup (Pre-empting Auto-Installs) ===" -ForegroundColor Cyan

# 1. PyTorch (CUDA 12.4)
Write-Host "-> [1/5] Installing PyTorch (CUDA 12.4)..." -ForegroundColor Yellow
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# 2. Forge公式要件のインストール (Pydantic 2.8.2 と FastAPI 0.104.1 を通す)
Write-Host "-> [2/5] Installing Forge requirements_versions.txt..." -ForegroundColor Yellow
& $PythonExe -m pip install -r requirements_versions.txt

# 3. 組み込み拡張機能やサブモジュールが裏で要求するパッケージを先回り導入
Write-Host "-> [3/5] Pre-installing CLIP, bitsandbytes, and preprocessor packages..." -ForegroundColor Yellow
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3
& $PythonExe -m pip install fvcore mediapipe onnxruntime svglib insightface handrefinerportable depth_anything depth_anything_v2

# 4. Pydantic 2.8.2 と FastAPI 0.104.1 の整合性を確保 (GradioのRootModel要件を満たす)
Write-Host "-> [4/5] Ensuring Pydantic 2.8.2 and FastAPI 0.104.1..." -ForegroundColor Yellow
& $PythonExe -m pip install "pydantic==2.8.2" "fastapi==0.104.1"

# 5. 【最重要】最後に NumPy 1.x のバイナリ整合性をピンポイントで確定 (scikit-image クラッシュ防止)
Write-Host "-> [5/5] Pinning NumPy 1.26.4 and scikit-image binary compatibility..." -ForegroundColor Yellow
& $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
& $PythonExe -m pip install --force-reinstall --no-deps scikit-image

Write-Host "`n=== [6/6] Pre-flight Health Check & Launch ===" -ForegroundColor Cyan

# 起動前整合性チェック（全ライブラリの整合性をテスト）
$healthCheckCode = @"
import numpy as np
import pydantic
from pydantic import RootModel
from skimage import exposure
import fastapi
import gradio

assert np.__version__.startswith('1.'), f'NumPy must be 1.x, found {np.__version__}'
assert pydantic.__version__.startswith('2.'), f'Pydantic must be 2.x, found {pydantic.__version__}'

print(f'[HealthCheck OK] All tests passed!')
print(f'  - NumPy: {np.__version__}')
print(f'  - Pydantic: {pydantic.__version__} (RootModel supported)')
print(f'  - FastAPI: {fastapi.__version__}')
print(f'  - Gradio: {gradio.__version__}')
"@

Write-Host "Running pre-flight environment check..." -ForegroundColor Yellow
& $PythonExe -c $healthCheckCode

# webui-user.bat に起動オプションを恒久固定 (--skip-install で勝手なpip更新を遮断)
$UserBat = "$InstallDir\webui-user.bat"
@"
@echo off
set PYTHON=%~dp0venv\Scripts\python.exe
set GIT=
set VENV_DIR=%~dp0venv
set COMMANDLINE_ARGS=--cuda-malloc --skip-install

call webui.bat
"@ | Set-Content -Path $UserBat -Encoding Ascii

Write-Host "`nwebui-user.bat configured with: --cuda-malloc --skip-install" -ForegroundColor Green
Write-Host "Starting Stable Diffusion WebUI Forge..." -ForegroundColor Green
Write-Host "URL: http://127.0.0.1:7860 (Please wait for models to initialize)" -ForegroundColor Green

cmd.exe /c "webui-user.bat"
'@ | Set-Content -Path $targetFile -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile