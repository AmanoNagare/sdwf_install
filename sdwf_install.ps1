# エラー発生時は停止
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo  = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/4] Forge の取得 ===" -ForegroundColor Cyan
if (-not (Test-Path "$InstallDir\.git")) {
    git clone $ForgeRepo $InstallDir
}
Set-Location $InstallDir

Write-Host "`n=== [2/4] Python 3.10 仮想環境と PyTorch の準備 ===" -ForegroundColor Cyan
# uv の確認と導入
if (-not (Get-Command "uv" -ErrorAction SilentlyContinue) -and -not (Test-Path "$HOME\.local\bin\uv.exe")) {
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
}
$uv = if (Get-Command "uv" -ErrorAction SilentlyContinue) { "uv" } else { "$HOME\.local\bin\uv.exe" }

$Python = "$InstallDir\venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    & $uv venv "$InstallDir\venv" --python 3.10 --seed
}

# PyTorch (CUDA 12.4) の高速導入
& $uv pip install torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/cu124" --python $Python

Write-Host "`n=== [3/4] NumPy 2.x の侵入ブロック設定 ===" -ForegroundColor Cyan
# 依存関係で NumPy 2.x が降ってくるのを防ぐ制約ファイルを配備
Set-Content -Path "$InstallDir\constraints.txt" -Value "numpy>=1.26.2,<2.0.0`nsetuptools<70" -Encoding Ascii
Set-Content -Path "$InstallDir\venv\pip.ini" -Value "[global]`nconstraint = $InstallDir\constraints.txt" -Encoding Ascii
$env:PIP_CONSTRAINT = "$InstallDir\constraints.txt"

# 起動バッチの作成
$BatContent = @"
@echo off
set PYTHON=%~dp0venv\Scripts\python.exe
set GIT=
set VENV_DIR=%~dp0venv
set COMMANDLINE_ARGS=--cuda-malloc
set PIP_CONSTRAINT=%~dp0constraints.txt
call webui.bat
"@
Set-Content -Path "$InstallDir\webui-user.bat" -Value $BatContent -Encoding Ascii

Write-Host "`n=== [4/4] Forge 起動処理 ===" -ForegroundColor Cyan
Write-Host "初回は必要な依存関係が自動インストールされます。URLが出るまでお待ちください。" -ForegroundColor Green

& $Python launch.py --cuda-malloc