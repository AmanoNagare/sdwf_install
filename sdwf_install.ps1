# ==============================================================================
# Stable Diffusion WebUI Forge: 汎用インストーラー & 起動スクリプト
# ==============================================================================
$ErrorActionPreference = "Stop"

# --- 【環境に合わせて変更する設定項目】 ---
$InstallDir = "$HOME\SD_Forge"        # インストール先（Dドライブ等にする場合は "D:\SD_Forge"）
$TorchCuda  = "cu124"                 # ドライバが古いPCの場合は "cu121" に変更
$LaunchArgs = "--cuda-malloc"         # NVIDIA 8GB以上のGPU向け（VRAM 6GB以下なら "--lowvram" を追加）
# ----------------------------------------

$ForgeRepo  = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/5] PC環境チェック ===" -ForegroundColor Cyan
if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "Gitがインストールされていません。Git for Windowsを導入してください。"
    exit 1
}

# ゾンビプロセスの停止と初期化
taskkill /F /IM python.exe /T 2>$null
if (-not (Test-Path "$InstallDir\.git")) {
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
    Write-Host "Forgeをクローンしています..." -ForegroundColor Yellow
    git clone $ForgeRepo $InstallDir
}
Set-Location $InstallDir

Write-Host "`n=== [2/5] uv による Python 3.10 仮想環境の作成 ===" -ForegroundColor Cyan
$uvExe = "$HOME\.local\bin\uv.exe"
if (-not (Test-Path $uvExe) -and -not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
}
$uv = if (Get-Command "uv" -ErrorAction SilentlyContinue) { "uv" } else { $uvExe }

$VenvDir = "$InstallDir\venv"
$Python  = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    & $uv venv $VenvDir --python 3.10 --seed
}

Write-Host "`n=== [3/5] PyTorch ($TorchCuda) の高速インストール ===" -ForegroundColor Cyan
& $uv pip install torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/$TorchCuda" --python $Python

Write-Host "`n=== [4/5] NumPy 2.x の侵入防止（物理ロック） ===" -ForegroundColor Cyan
# 全PC共通: NumPy 2.x による skimage / OpenCV のクラッシュを未然に防ぐ
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

# 恒久起動バッチ（webui-user.bat）の生成
@"
@echo off
set PYTHON=%~dp0venv\Scripts\python.exe
set GIT=
set VENV_DIR=%~dp0venv
set COMMANDLINE_ARGS=$LaunchArgs
set PIP_CONSTRAINT=%~dp0constraints.txt

call webui.bat
"@ | Set-Content -Path "$InstallDir\webui-user.bat" -Encoding Ascii

Write-Host "`n=== [5/5] Forge の自動インストールと初回起動 ===" -ForegroundColor Cyan
Write-Host "初回は必要なライブラリが自動ダウンロードされます。URLが表示されるまでお待ちください。" -ForegroundColor Green
& $Python launch.py $LaunchArgs.Split(" ")