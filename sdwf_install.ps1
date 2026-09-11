$targetFile = "$PWD\forge_installer.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: Optimized Installer & Launcher
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/5] Checking Environment ===" -ForegroundColor Cyan
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

Write-Host "`n=== [2/5] Git Clone / Sync ===" -ForegroundColor Cyan
if (-not (Test-Path $InstallDir)) {
    git clone $ForgeRepo $InstallDir
}
Set-Location $InstallDir

Write-Host "`n=== [3/5] Python Environment Setup ===" -ForegroundColor Cyan
$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    & $uv venv $VenvDir --python 3.10 --seed
}

Write-Host "`n=== [4/5] Pre-installing Packages & Locking NumPy 1.x ===" -ForegroundColor Cyan
# PyTorch (CUDA 12.4)
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# Forge本体の依存関係を先行適用
if (Test-Path "requirements_versions.txt") {
    & $uv pip install -r requirements_versions.txt --python $PythonExe
}

# CLIP関連の先行ビルド
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch

# 重要: すべての依存関係解決後に NumPy を 1.x 系に固定
Write-Host "Locking NumPy to <2.0 to prevent skimage crash..." -ForegroundColor Yellow
& $uv pip install "numpy<2" --python $PythonExe

Write-Host "`n=== [5/5] Launching Forge (RTX A4000 Optimized) ===" -ForegroundColor Cyan
$env:PYTHON = $PythonExe
# RTX A4000 (16GB) 向けに高速化フラグを指定
$env:COMMANDLINE_ARGS = "--cuda-malloc"

Write-Host "Starting WebUI Forge..." -ForegroundColor Green
Write-Host "Access URL: http://127.0.0.1:7860" -ForegroundColor Green
cmd.exe /c "webui-user.bat"
'@ | Set-Content -Path $targetFile -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile