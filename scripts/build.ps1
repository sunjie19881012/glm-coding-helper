param(
    [string]$OutputDir = "dist",
    [string]$Stamp = "",
    [switch]$SkipPortable,
    [switch]$Quick
)

<#
.SYNOPSIS
    GLM Coding Helper release build script
.DESCRIPTION
    Builds online-installer and portable-cpu packages from repo source
    and resource/ environment directory. Outputs to dist/.

    Usage:
      .\scripts\build.ps1                     # both packages
      .\scripts\build.ps1 -SkipPortable       # online-installer only
      .\scripts\build.ps1 -Quick              # skip import validation
#>

$ErrorActionPreference = "Stop"
$Root = (Get-Item $PSScriptRoot).Parent.FullName
$Resource = Join-Path $Root "resource"
$OutRoot = Join-Path $Root $OutputDir

# timestamp
if (-not $Stamp) { $Stamp = Get-Date -Format "yyyyMMdd_HHmmss" }

# source items shared by both packages
$SourceItems = @(
    "glm-coding-helper.user.js"
    "start-backend.cmd"
    "install-env.cmd"
    "one-click-start.cmd"
    "README.md"
    "CHANGELOG.md"
    "LICENSE"
    "requirements-backend-cpu.txt"
    "requirements-backend-gpu.txt"
    "scripts"
    "models"
)

# env directories only in portable
$EnvDirs = @(
    ".venv_paddle"
    ".paddle_home"
    ".paddlex_cache_cpu"
)

New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null

function Copy-Items {
    param([string]$TargetDir, [string[]]$Items)
    foreach ($item in $Items) {
        $src = Join-Path $Root $item
        if (-not (Test-Path $src)) {
            Write-Host "  SKIP $item (not found)"
            continue
        }
        $dst = Join-Path $TargetDir $item
        Write-Host "  COPY $item"
        if ((Get-Item $src).PSIsContainer) {
            robocopy $src $dst /E /XD __pycache__ /XF *.pyc *.pyo /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $item" }
        } else {
            $dstParent = Split-Path -Parent $dst
            if ($dstParent) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

# ===== 1. Online-installer (source + models, no Python env) =====
Write-Host "`n=== Building online-installer ===" -ForegroundColor Cyan
$OnlineName = "glm-coding-helper-online-installer-$Stamp"
$OnlineDir = Join-Path $OutRoot $OnlineName
if (Test-Path $OnlineDir) { Remove-Item -LiteralPath $OnlineDir -Recurse -Force }
New-Item -ItemType Directory -Path $OnlineDir | Out-Null

Copy-Items -TargetDir $OnlineDir -Items $SourceItems

New-Item -ItemType Directory -Path (Join-Path $OnlineDir "dataset") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OnlineDir "logs") -Force | Out-Null

$OnlineReadme = @"
GLM Coding Helper online installer package

Recommended:
1. Install or update Tampermonkey script from glm-coding-helper.user.js.
2. Double-click one-click-start.cmd.
3. It will install CPU/GPU backend dependencies automatically when missing, then start the backend.

Manual:
- install-env.cmd installs CPU backend environment.
- start-backend.cmd starts CPU backend after environment exists.
"@
Set-Content -LiteralPath (Join-Path $OnlineDir "ONLINE_INSTALLER_README.txt") -Value $OnlineReadme -Encoding UTF8

$OnlineZip = Join-Path $OutRoot "$OnlineName.zip"
if (Test-Path $OnlineZip) { Remove-Item -LiteralPath $OnlineZip -Force }
Write-Host "  Zipping online-installer..."
Compress-Archive -Path "$OnlineDir\*" -DestinationPath $OnlineZip -CompressionLevel Optimal
$size = (Get-Item $OnlineZip).Length
Write-Host "  Done ($([math]::Round($size/1MB, 1)) MB)" -ForegroundColor Green

# ===== 2. Portable-cpu (includes Python env) =====
if (-not $SkipPortable) {
    Write-Host "`n=== Building portable-cpu ===" -ForegroundColor Cyan

    $VenvPy = Join-Path $Resource ".venv_paddle\Scripts\python.exe"
    if (-not (Test-Path $VenvPy)) {
        throw "Missing .venv_paddle in resource/. Run install-env.cmd first or copy from existing portable package."
    }
    $Weight = Join-Path $Root "models\weights\yolo-captcha-detector.pt"
    if (-not (Test-Path $Weight)) {
        throw "Missing model weight: $Weight"
    }

    if (-not $Quick) {
        Write-Host "  Validating Python imports..."
        & $VenvPy -c "import ultralytics, paddleocr, paddlex, cv2, PIL, numpy; print('imports ok')"
        if ($LASTEXITCODE -ne 0) {
            throw "resource/.venv_paddle imports failed. The environment may be incomplete."
        }
    }

    $PortableName = "glm-coding-helper-portable-cpu-$Stamp"
    $PortableDir = Join-Path $OutRoot $PortableName
    if (Test-Path $PortableDir) { Remove-Item -LiteralPath $PortableDir -Recurse -Force }
    New-Item -ItemType Directory -Path $PortableDir | Out-Null

    Copy-Items -TargetDir $PortableDir -Items $SourceItems

    Write-Host "  Copying environment directories..."
    foreach ($dir in $EnvDirs) {
        $src = Join-Path $Resource $dir
        if (-not (Test-Path $src)) {
            Write-Host "  SKIP $dir (not found in resource/)"
            continue
        }
        Write-Host "  COPY resource/$dir"
        robocopy $src (Join-Path $PortableDir $dir) /E /XD __pycache__ /XF *.pyc *.pyo /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $dir" }
    }

    New-Item -ItemType Directory -Path (Join-Path $PortableDir "dataset") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $PortableDir "logs") -Force | Out-Null

    $PortableReadme = @"
GLM Coding Helper portable CPU package

1. Install or update Tampermonkey script from glm-coding-helper.user.js.
2. Double-click start-backend.cmd.
3. Open https://www.bigmodel.cn/glm-coding.

This package includes the CPU Python environment and local model files.
"@
    Set-Content -LiteralPath (Join-Path $PortableDir "PORTABLE_README.txt") -Value $PortableReadme -Encoding UTF8

    $PortableZip = Join-Path $OutRoot "$PortableName.zip"
    if (Test-Path $PortableZip) { Remove-Item -LiteralPath $PortableZip -Force }
    Write-Host "  Zipping portable (source ~1.5 GB, may take minutes)..."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Compress-Archive -Path "$PortableDir\*" -DestinationPath $PortableZip -CompressionLevel Optimal
    $sw.Stop()
    $zsize = (Get-Item $PortableZip).Length
    Write-Host "  Done in $([math]::Round($sw.Elapsed.TotalSeconds))s ($([math]::Round($zsize/1MB, 1)) MB)" -ForegroundColor Green
}

# results
Write-Host "`n=== Build complete ===" -ForegroundColor Cyan
Get-ChildItem $OutRoot -Filter "*.zip" | ForEach-Object {
    Write-Host "  $($_.Name) ($([math]::Round($_.Length/1MB, 1)) MB)"
}
