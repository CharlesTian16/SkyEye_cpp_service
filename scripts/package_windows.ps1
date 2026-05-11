param(
    [string]$OutputDir = "dist/pilot_windows",
    [string]$PreferredBuildDir = "",
    [string]$VcpkgRoot = "D:/vcpkg/installed/x64-windows",
    [string]$OrtDir = "D:/onnxruntime-win-x64-gpu-1.24.1"
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $OutputDir

function Get-ExeRoot {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $path = Join-Path $root $candidate
        if (Test-Path (Join-Path $path "pilot.exe")) {
            return $path
        }
    }
    return $null
}

$candidateRoots = @()
if (-not [string]::IsNullOrWhiteSpace($PreferredBuildDir)) {
    $candidateRoots += $PreferredBuildDir
}
$candidateRoots += @(
    "pilot\x64\Debug",
    "pilot\x64\Release",
    "out\build\windows-release",
    "out\build\windows-base"
)

$buildRoot = Get-ExeRoot -Candidates $candidateRoots
if (-not $buildRoot) {
    throw "pilot.exe not found in known build folders. Use -PreferredBuildDir to point at the folder containing pilot.exe."
}

if (Test-Path $dist) {
    Remove-Item -Recurse -Force $dist
}

$dirs = @(
    $dist,
    (Join-Path $dist "bin"),
    (Join-Path $dist "runtime"),
    (Join-Path $dist "runtime\ffmpeg"),
    (Join-Path $dist "client"),
    (Join-Path $dist "models"),
    (Join-Path $dist "config"),
    (Join-Path $dist "output"),
    (Join-Path $dist "temp")
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Copy-Item -Force (Join-Path $buildRoot "pilot.exe") (Join-Path $dist "bin\pilot.exe")

function Copy-DllToPackage {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$DllFile
    )

    $targets = @(
        (Join-Path $dist "runtime\$($DllFile.Name)"),
        (Join-Path $dist "bin\$($DllFile.Name)")
    )

    foreach ($target in $targets) {
        Copy-Item -Force $DllFile.FullName $target
    }
}

foreach ($dll in Get-ChildItem -Path $buildRoot -Filter *.dll -File -ErrorAction SilentlyContinue) {
    Copy-DllToPackage -DllFile $dll
}

$extraDllRoots = @(
    (Join-Path $VcpkgRoot "bin"),
    (Join-Path $VcpkgRoot "debug\bin"),
    (Join-Path $OrtDir "lib")
)
foreach ($extraRoot in $extraDllRoots) {
    if (-not (Test-Path $extraRoot)) { continue }
    foreach ($dll in Get-ChildItem -Path $extraRoot -Filter *.dll -File -ErrorAction SilentlyContinue) {
        $runtimeDest = Join-Path $dist "runtime\$($dll.Name)"
        $binDest = Join-Path $dist "bin\$($dll.Name)"
        if (-not (Test-Path $runtimeDest) -or -not (Test-Path $binDest)) {
            Copy-DllToPackage -DllFile $dll
        }
    }
}

$models = @{
    "i3d\models\a320_new_full.onnx" = "models\a320_new_full.onnx"
    "algos\tridet_a320.onnx" = "models\tridet_a320.onnx"
    "yolo\config\best.onnx" = "models\best.onnx"
}
foreach ($pair in $models.GetEnumerator()) {
    $src = Join-Path $root $pair.Key
    $dst = Join-Path $dist $pair.Value
    if (-not (Test-Path $src)) {
        throw "Model not found: $src"
    }
    Copy-Item -Force $src $dst
}

Copy-Item -Force (Join-Path $root "client\index.html") (Join-Path $dist "client\index.html")
Copy-Item -Force (Join-Path $root "config\pilot_deploy.properties") (Join-Path $dist "config\pilot_deploy.properties")

$ffmpegPath = $null
foreach ($name in @("ffmpeg.exe", "ffmpeg")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        $ffmpegPath = $cmd.Source
        break
    }
}

if ($ffmpegPath) {
    Copy-Item -Force $ffmpegPath (Join-Path $dist "runtime\ffmpeg\ffmpeg.exe")
} else {
    Write-Warning "ffmpeg.exe not found in PATH. Put it into runtime\ffmpeg\ffmpeg.exe manually."
}

$note = @"
Pilot Windows deployment package

Run:
  bin\pilot.exe

Open:
  http://127.0.0.1:8080/

Target machine requirements:
- Windows x64 with desktop session
- VC++ Redistributable
- NVIDIA driver
- CUDA / cuDNN compatible with the bundled ONNX Runtime GPU build
- ffmpeg.exe in runtime\ffmpeg or on PATH
- Launch-time DLLs are copied into both bin\ and runtime\; start the app from bin\pilot.exe
"@

Set-Content -Path (Join-Path $dist "README_DEPLOY.txt") -Value $note -Encoding UTF8

Write-Host "Deployment package created at: $dist"
Write-Host "Build root used: $buildRoot"
