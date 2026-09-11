$targetFile = "$PWD\forge_installer.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: All-in-One Installer & Launcher
# (Optimized for School PC / Lab Environment)
# ==============================================================================
$ErrorActionPreference = "Stop"

# --- Configuration ---
$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [1/6] School PC Pre-flight Checks" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check Git
if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "[Error] Git is not installed or not added to PATH. Please install Git first."
    exit 1
}
Write-Host "[OK] Git detected: $((Get-Command git).Source)" -ForegroundColor Green

# 2. Check Disk Free Space (At least 15 GB recommended)
$drive = (Get-Item $HOME).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 2)
if ($freeGB -lt 15) {
    Write-Warning "[Warning] Free disk space on $($drive.Name): is ${freeGB} GB. (At least 15-20 GB is recommended)"
} else {
    Write-Host "[OK] Disk space available: ${freeGB} GB" -ForegroundColor Green
}

# 3. Check NVIDIA GPU
if (Get-Command "nvidia-smi" -ErrorAction SilentlyContinue) {
    Write-Host "[OK] NVIDIA GPU detected via nvidia-smi." -ForegroundColor Green
} else {
    Write-Warning "[Warning] nvidia-smi was not found. If this PC has no NVIDIA GPU, execution will be CPU-only or may fail."
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [2/6] Setting up 'uv' Package Manager" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$uvExe = "$HOME\.local\bin\uv.exe"
if (Get-Command "uv" -ErrorAction SilentlyContinue) {
    $uv = "uv"
} elseif (Test-Path $uvExe) {
    $uv = $uvExe
} else {
    Write-Host "Installing uv to user directory ($HOME\.local\bin)..." -ForegroundColor Yellow
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $uv = $uvExe
}
$env:Path = "$HOME\.local\bin;$env:Path"
Write-Host "[OK] uv is ready: $uv" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [3/6] Cloning WebUI Forge Repository" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    Write-Host "Cloning repo into $InstallDir..." -ForegroundColor Yellow
    git clone $ForgeRepo $InstallDir
} else {
    Write-Host "[OK] Directory already exists: $InstallDir" -ForegroundColor Green
}
Set-Location $InstallDir

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [4/6] Creating Python 3.10 Virtual Environment (with seed)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"

if (-not (Test-Path $PythonExe)) {
    Write-Host "Creating venv with pip, setuptools, and wheel pre-seeded..." -ForegroundColor Yellow
    & $uv venv $VenvDir --python 3.10 --seed
} else {
    Write-Host "[OK] Virtual environment already exists at $VenvDir" -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [5/6] Pre-installing PyTorch & Resolving Known Conflicts" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# PyTorch with CUDA 12.4
Write-Host "-> Installing PyTorch (CUDA 12.4)..." -ForegroundColor Yellow
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# Fix: Prevent skimage binary crash by pinning NumPy < 2.0
Write-Host "-> Pinning NumPy < 2.0 (prevents skimage ValueError)..." -ForegroundColor Yellow
& $PythonExe -m pip install "numpy<2"

# Fix: Prevent CLIP build failure by setting setuptools < 70
Write-Host "-> Installing compatible setuptools and wheel..." -ForegroundColor Yellow
& $PythonExe -m pip install "setuptools<70" wheel

# Fix: Install OpenAI CLIP without build isolation
Write-Host "-> Installing OpenAI CLIP (--no-build-isolation)..." -ForegroundColor Yellow
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip

# Pre-install open-clip
Write-Host "-> Installing open-clip-torch..." -ForegroundColor Yellow
& $PythonExe -m pip install open-clip-torch

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [6/6] Launching Stable Diffusion WebUI Forge" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$env:PYTHON = $PythonExe

# VRAMが少ないPC（4GB〜6GB）の場合は "--lowvram" を追加してください
# 同じ教室の別PCからブラウザで開く場合は "--listen" を追加してください
$env:COMMANDLINE_ARGS = ""

Write-Host "Starting WebUI Forge..." -ForegroundColor Green
Write-Host "Access URL: http://127.0.0.1:7860" -ForegroundColor Green
cmd.exe /c "webui-user.bat"
'@ | Set-Content -Path $targetFile -Encoding UTF8

Write-Host "Generated: $targetFile" -ForegroundColor Green
Write-Host "Executing under ExecutionPolicy Bypass..." -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile