# ==============================================================================
# Stable Diffusion WebUI Forge: 完全自動・一発起動インストーラー
# ==============================================================================
$ErrorActionPreference = "Stop"

$InstallDir = "$HOME\SD_Forge"
$ForgeRepo  = "https://github.com/lllyasviel/stable-diffusion-webui-forge.git"

Write-Host "=== [1/5] リポジトリの準備 ===" -ForegroundColor Cyan
Get-Process -Name "python", "pythonw" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "Gitがインストールされていません。Git for Windowsを導入してください。"
    exit 1
}

if (-not (Test-Path "$InstallDir\.git")) {
    git clone $ForgeRepo $InstallDir
}
Set-Location $InstallDir

Write-Host "`n=== [2/5] uv による Python 3.10 仮想環境の作成 ===" -ForegroundColor Cyan
if (-not (Get-Command "uv" -ErrorAction SilentlyContinue) -and -not (Test-Path "$HOME\.local\bin\uv.exe")) {
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
}
$uv = if (Get-Command "uv" -ErrorAction SilentlyContinue) { "uv" } else { "$HOME\.local\bin\uv.exe" }

$VenvDir   = "$InstallDir\venv"
$PythonExe = "$VenvDir\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) {
    & $uv venv $VenvDir --python 3.10 --seed
}

Write-Host "`n=== [3/5] PyTorch & コアライブラリの導入 ===" -ForegroundColor Cyan
# PyTorch (CUDA 12.4)
& $uv pip install torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/cu124" --python $PythonExe

# Forge公式要件の導入
& $PythonExe -m pip install -r requirements_versions.txt

# 【最重要】公式の古い FastAPI (0.104.1) を Pydantic 2.8 対応版へ即座に更新
& $PythonExe -m pip install "fastapi>=0.112.0"

Write-Host "`n=== [4/5] NumPy 2.x の侵入遮断 & 画像処理ライブラリの整合 ===" -ForegroundColor Cyan
# 1. 恒久的な制約ファイルと pip.ini の配備（以降の pip 実行で NumPy 2.x を完全阻止）
$ConstraintFile = "$InstallDir\constraints.txt"
Set-Content -Path $ConstraintFile -Value "numpy>=1.26.2,<2.0.0`nsetuptools<70" -Encoding Ascii

$PipIni = "$VenvDir\pip.ini"
Set-Content -Path $PipIni -Value "[global]`nconstraint = $ConstraintFile" -Encoding Ascii
$env:PIP_CONSTRAINT = $ConstraintFile

# 2. scikit-image と関連モジュールを NumPy 1.x の下で確定
& $PythonExe -m pip install scipy imageio tifffile networkx
& $PythonExe -m pip install --force-reinstall --no-deps "numpy==1.26.4"
& $PythonExe -m pip install --force-reinstall --no-deps scikit-image

# 3. CLIP・bitsandbytes の事前導入
& $PythonExe -m pip install "setuptools<70" wheel
& $PythonExe -m pip install --no-build-isolation https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip
& $PythonExe -m pip install open-clip-torch bitsandbytes==0.45.3

# 4. 次回以降直接起動するための webui-user.bat 生成
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

Write-Host "`n=== [5/5] WebUI Forge の起動 ===" -ForegroundColor Cyan
Write-Host "すべての整合性が完了しました。起動しています..." -ForegroundColor Green
Write-Host "URL: http://127.0.0.1:7860 が開くまでお待ちください。" -ForegroundColor Green

& $PythonExe launch.py --cuda-malloc