# ==============================================================================
# Stable Diffusion WebUI Forge: 他PC用・汎用セットアップスクリプト
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo  = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/5] 前準備・リポジトリ取得 ===" -ForegroundColor Cyan
Get-Process -Name "python", "pythonw" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "Gitがインストールされていません。Git for Windowsを導入してください。"
    exit 1
}

if (-not (Test-Path "$InstallDir\.git")) {
    git clone $ForgeRepo $InstallDir
}
Set-Location $InstallDir

Write-Host "`n=== [2/5] uv による Python 3.10 環境構築 ===" -ForegroundColor Cyan
if (-not (Get-Command "uv" -ErrorAction SilentlyContinue) -and -not (Test-Path "$HOME\.local\bin\uv.exe")) {
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
}
$uv = if (Get-Command "uv" -ErrorAction SilentlyContinue) { "uv" } else { "$HOME\.local\bin\uv.exe" }

$VenvDir   = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    & $uv venv $VenvDir --python 3.10 --seed
}

Write-Host "`n=== [3/5] PyTorch & コア要件の高速導入 ===" -ForegroundColor Cyan
# PyTorch (CUDA 12.4)
& $uv pip install torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/cu124" --python $PythonExe

# Forge公式要件（Gradio 4系・Pydantic 2.8.2・FastAPI 0.104.1が正常に入ります）
& $PythonExe -m pip install -r requirements_versions.txt

Write-Host "`n=== [4/5] NumPy 2.x 侵入防止ロックと scikit-image の整合 ===" -ForegroundColor Cyan
# 1. constraints.txt と pip.ini で NumPy 2.x の侵入を完全遮断
$ConstraintFile = "$InstallDir\constraints.txt"
Set-Content -Path $ConstraintFile -Value "numpy>=1.26.2,<2.0.0`nsetuptools<70" -Encoding Ascii

$PipIni = "$VenvDir\pip.ini"
Set-Content -Path $PipIni -Value "[global]`nconstraint = $ConstraintFile" -Encoding Ascii
$env:PIP_CONSTRAINT = $ConstraintFile

# 2. scikit-image と画像処理ライブラリを NumPy 1.x の下で固定
& $PythonExe -m pip install scipy imageio tifffile networkx
& $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
& $PythonExe -m pip install --force-reinstall --no-deps scikit-image

# 3. CLIP・bitsandbytes の事前ビルド
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3

# 4. 2回目以降の起動用バッチファイル作成
$BatPath = "$InstallDir\webui-user.bat"
$BatLines = @(
    "@echo off",
    "set PYTHON=%~dp0venv\Scripts\python.exe",
    "set GIT=",
    "set VENV_DIR=%~dp0venv",
    "set COMMANDLINE_ARGS=--cuda-malloc",
    "set PIP_CONSTRAINT=%~dp0constraints.txt",
    "call webui.bat"
)
Set-Content -Path $BatPath -Value ($BatLines -join "`r`n") -Encoding Ascii

Write-Host "`n=== [5/5] Stable Diffusion WebUI Forge 起動 ===" -ForegroundColor Cyan
Write-Host "起動処理を開始します。http://127.0.0.1:7860 が表示されるまでお待ちください。" -ForegroundColor Green

& $PythonExe launch.py --cuda-malloc