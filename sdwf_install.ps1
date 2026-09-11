# ==============================================================================
# Stable Diffusion WebUI Forge: Clean-Slate Installer & Launcher
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/6] Cleaning Up Old Processes and Files ===" -ForegroundColor Cyan

# 1. 残留している Python/CMD プロセスを強制終了
Get-Process -Name "python", "cmd" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Path -like "*SD_Forge*" } | 
    Stop-Process -Force -ErrorAction SilentlyContinue

# 2. 既存のディレクトリを完全削除してまっさらにする
if (Test-Path $InstallDir) {
    Write-Host "Removing existing SD_Forge directory to start clean..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Write-Host "[OK] Clean-slate ready." -ForegroundColor Green

Write-Host "`n=== [2/6] Environment Pre-check & uv Setup ===" -ForegroundColor Cyan
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
    Write-Host "Setting up uv..." -ForegroundColor Yellow
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $uv = $uvExe
}
$env:Path = "$HOME\.local\bin;$env:Path"
Write-Host "[OK] Git and uv verified." -ForegroundColor Green

Write-Host "`n=== [3/6] Clean Git Clone ===" -ForegroundColor Cyan
git clone $ForgeRepo $InstallDir
Set-Location $InstallDir

Write-Host "`n=== [4/6] Setting Up Python 3.10 Virtual Environment ===" -ForegroundColor Cyan
$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
& $uv venv $VenvDir --python 3.10 --seed

# 必須制約ファイルを作成 (NumPy 2.x と setuptools 70+ のみを恒久ブロックし、Pydantic/FastAPIは公式仕様に従わせる)
$ConstraintFile = "$InstallDir\constraints.txt"
@"
numpy>=1.26.2,<2.0.0
setuptools<70
"@ | Set-Content -Path $ConstraintFile -Encoding Ascii

# pip.ini を作成し、以降 Forge や拡張機能が裏で呼ぶ全ての pip に制約を強制
$PipIni = "$VenvDir\pip.ini"
@"
[global]
constraint = $ConstraintFile
"@ | Set-Content -Path $PipIni -Encoding Ascii
$env:PIP_CONSTRAINT = $ConstraintFile

Write-Host "`n=== [5/6] Installing Dependencies ===" -ForegroundColor Cyan

# 1. PyTorch (CUDA 12.4)
Write-Host "-> Installing PyTorch..." -ForegroundColor Yellow
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# 2. Forge公式要件の一括インストール（pydantic==2.8.2 と fastapi==0.104.1 が正常に入ります）
Write-Host "-> Installing Forge core requirements..." -ForegroundColor Yellow
& $PythonExe -m pip install -r requirements_versions.txt

# 3. CLIP & 関連ツールの先行ビルド
Write-Host "-> Pre-building CLIP and sub-modules..." -ForegroundColor Yellow
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3

# 4. scikit-image と NumPy 1.x のバイナリ整合性を確定
Write-Host "-> Securing NumPy 1.x / scikit-image binary compatibility..." -ForegroundColor Yellow
& $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
& $PythonExe -m pip install --force-reinstall --no-deps scikit-image

Write-Host "`n=== [6/6] Launching Stable Diffusion WebUI Forge ===" -ForegroundColor Cyan

# webui-user.bat の恒久固定（--cuda-malloc を付与）
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

Write-Host "Starting WebUI Forge..." -ForegroundColor Green
Write-Host "Waiting for URL (http://127.0.0.1:7860) to appear..." -ForegroundColor Green
cmd.exe /c "webui-user.bat"