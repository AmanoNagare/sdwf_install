$targetFile = "$PWD\setup_forge.ps1"

@'
# ==============================================================================
# Stable Diffusion WebUI Forge: 汎用セットアップ＆起動スクリプト
# ==============================================================================
$ErrorActionPreference = "Stop"

# --- 設定項目 ---
$InstallDir = "$HOME\SD_Forge"
$ForgeRepo  = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
$TorchCuda  = "cu124"
$LaunchArgs = "--cuda-malloc"
# ----------------

Write-Host "=== [1/5] 前処理・リポジトリ取得 ===" -ForegroundColor Cyan

# PowerShellネイティブコマンドでプロセスを終了（エラーは完全に無視される）
Get-Process -Name "python", "pythonw" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "Gitがインストールされていません。Git for Windowsを導入してください。"
    exit 1
}

if (-not (Test-Path "$InstallDir\.git")) {
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
    Write-Host "Forgeリポジトリをクローンしています..." -ForegroundColor Yellow
    git clone $ForgeRepo $InstallDir
} else {
    Write-Host "[OK] 既存のForgeリポジトリを検出: $InstallDir" -ForegroundColor Green
}
Set-Location $InstallDir

Write-Host "`n=== [2/5] uv による Python 3.10 仮想環境の構築 ===" -ForegroundColor Cyan
$uvExe = "$HOME\.local\bin\uv.exe"
if (-not (Test-Path $uvExe) -and -not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
    Write-Host "uv をセットアップしています..." -ForegroundColor Yellow
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
}
$uv = if (Get-Command "uv" -ErrorAction SilentlyContinue) { "uv" } else { $uvExe }

$VenvDir   = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    & $uv venv $VenvDir --python 3.10 --seed
}

Write-Host "`n=== [3/5] PyTorch & コア要件の導入 ===" -ForegroundColor Cyan
Write-Host "-> PyTorch ($TorchCuda) インストール中..." -ForegroundColor Yellow
& $uv pip install torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/$TorchCuda" --python $PythonExe

Write-Host "-> Forge公式依存関係インストール中..." -ForegroundColor Yellow
& $PythonExe -m pip install -r requirements_versions.txt

Write-Host "`n=== [4/5] 競合防止ロック & ライブラリ整合性固定 ===" -ForegroundColor Cyan
# 1. pip.ini による NumPy 2.x の侵入ブロック
$ConstraintFile = "$InstallDir\constraints.txt"
@"
numpy>=1.26.2,<2.0.0
setuptools<70
"@ | Set-Content -Path $ConstraintFile -Encoding Ascii

$env:PIP_CONSTRAINT = $ConstraintFile
@"
[global]
constraint = $ConstraintFile
"@ | Set-Content -Path "$VenvDir\pip.ini" -Encoding Ascii

# 2. scikit-image と NumPy 1.x の整合性を確定
Write-Host "-> scikit-image 及び関連ライブラリを固定中..." -ForegroundColor Yellow
& $PythonExe -m pip install scipy imageio tifffile networkx
& $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
& $PythonExe -m pip install --force-reinstall --no-deps scikit-image

# 3. 頻出モジュールの事前ビルド
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3

# 4. 次回以降の直接起動用バッチ生成
$UserBat = "$InstallDir\webui-user.bat"
@"
@echo off
set PYTHON=%~dp0venv\Scripts\python.exe
set GIT=
set VENV_DIR=%~dp0venv
set COMMANDLINE_ARGS=$LaunchArgs
set PIP_CONSTRAINT=%~dp0constraints.txt

call webui.bat
"@ | Set-Content -Path $UserBat -Encoding Ascii

Write-Host "`n=== [5/5] Stable Diffusion WebUI Forge 起動 ===" -ForegroundColor Cyan
Write-Host "初期化完了後、ブラウザで http://127.0.0.1:7860 を開いてください。" -ForegroundColor Green

& $PythonExe launch.py $LaunchArgs.Split(" ")
'@ | Set-Content -Path $targetFile -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetFile