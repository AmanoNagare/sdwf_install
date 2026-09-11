$targetFile = "$PWD\forge_installer.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: Fully Fixed Installer & Launcher
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/5] Environment Pre-check ===" -ForegroundColor Cyan
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

Write-Host "`n=== [2/5] Repository Verification ===" -ForegroundColor Cyan
if (-not (Test-Path "$InstallDir\.git")) {
    Write-Host "Cloning Forge repository..." -ForegroundColor Yellow
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
    git clone $ForgeRepo $InstallDir
} else {
    Write-Host "[OK] Repository verified: $InstallDir" -ForegroundColor Green
}
Set-Location $InstallDir

Write-Host "`n=== [3/5] Python Virtual Environment Setup ===" -ForegroundColor Cyan
$VenvDir = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    & $uv venv $VenvDir --python 3.10 --seed
}

Write-Host "`n=== [4/5] Fixing Constraints & Pre-installing Packages ===" -ForegroundColor Cyan

# 1. 正しい制約ファイルを作成（fastapiの制限を削除し、numpyとpydanticのみ固定）
$ConstraintFile = "$InstallDir\constraints.txt"
@"
numpy>=1.26.2,<2.0.0
pydantic>=1.10.13,<2.0.0
setuptools<70
"@ | Set-Content -Path $ConstraintFile -Encoding Ascii

# 2. pip.ini を作成して venv 内のすべての pip 実行に制約を強制
$PipDir = "$VenvDir"
$PipIni = "$PipDir\pip.ini"
@"
[global]
constraint = $ConstraintFile
"@ | Set-Content -Path $PipIni -Encoding Ascii
$env:PIP_CONSTRAINT = $ConstraintFile

# 3. PyTorch (CUDA 12.4)
& $uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 --python $PythonExe

# 4. Forge公式要件のインストール (fastapi==0.104.1 を通す)
if (Test-Path "requirements_versions.txt") {
    & $PythonExe -m pip install -r requirements_versions.txt
}

# 5. ビルド競合を起こしやすい個別ライブラリを明示導入
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3

# 6. skimage と numpy のバイナリ整合性を確定
& $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
& $PythonExe -m pip install --force-reinstall --no-deps scikit-image

Write-Host "`n=== [5/5] Pre-launch Health Check & Launch ===" -ForegroundColor Cyan

# 起動前ヘルスチェック
$healthScript = @"
import numpy
assert numpy.__version__.startswith('1.'), 'NumPy must be 1.x'
import pydantic
assert pydantic.__version__.startswith('1.'), 'Pydantic must be 1.x'
from skimage import exposure
import fastapi
print('Environment Health: All checks passed (NumPy, Pydantic, skimage, FastAPI)')
"@
& $PythonExe -c $healthScript

# webui-user.bat に起動引数と制約を反映
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

Write-Host "`nStarting Stable Diffusion WebUI Forge..." -ForegroundColor Green
Write-Host "Access URL will appear below (usually http://127.0.0.1:7860)" -ForegroundColor Green
cmd.exe /c "webui-user.bat"
'@ | Set-Content -Path $targetFile -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile