param(
  [Parameter(Mandatory = $true)]
  [string]$Source,

  [Parameter(Mandatory = $true)]
  [string]$Destination,

  [Parameter(Mandatory = $false)]
  [string]$Container = "halo",

  [Parameter(Mandatory = $false)]
  [string]$RemotePath = "/root/.halo2/themes/theme-fuwari"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Source = (Resolve-Path -LiteralPath $Source).Path

# Step 1: Use docker exec to create the full directory tree inside the container.
# This avoids the Windows Docker bind-mount bug where mkdir creates flat filenames.
Write-Output "Creating directory structure via docker exec..."
docker exec $Container rm -rf $RemotePath
docker exec $Container mkdir -p $RemotePath

# Collect all subdirectories from source dirs that need copying
$dirsToCopy = @("i18n", "templates")
foreach ($d in $dirsToCopy) {
  $srcDir = Join-Path $Source $d
  if (-not (Test-Path -LiteralPath $srcDir)) { throw "Source not found: $srcDir" }
  # Get all subdirectories relative to source
  $subDirs = Get-ChildItem -Path $srcDir -Directory -Recurse | ForEach-Object {
    $_.FullName.Substring($Source.Length).TrimStart('\', '/').Replace('\', '/')
  }
  # Create each subdirectory inside the container
  docker exec $Container mkdir -p "$RemotePath/$($d.Replace('\','/'))"
  foreach ($sd in $subDirs) {
    docker exec $Container mkdir -p "$RemotePath/$sd"
  }
}

# Step 2: Copy files via the bind-mount path (which now has proper directories).
# This keeps the files on the host filesystem for Vite hot-reload compatibility.
Write-Output "Copying files to bind-mount path..."

$filesToCopy = @("LICENSE", "README.md", "settings.yaml", "theme.yaml")
foreach ($f in $filesToCopy) {
  $srcFile = Join-Path $Source $f
  if (-not (Test-Path -LiteralPath $srcFile)) { throw "Source file not found: $srcFile" }
  Copy-Item -LiteralPath $srcFile -Destination (Join-Path $Destination $f) -Force
}

foreach ($d in $dirsToCopy) {
  $srcDir = Join-Path $Source $d
  # Copy all files (not dirs) preserving relative path
  Get-ChildItem -Path $srcDir -File -Recurse | ForEach-Object {
    $relPath = $_.FullName.Substring($srcDir.Length).TrimStart('\', '/')
    $destFile = Join-Path (Join-Path $Destination $d) $relPath
    Copy-Item -LiteralPath $_.FullName -Destination $destFile -Force
  }
}

Write-Output ""
Write-Output "Theme deployed to: $Destination"
Write-Output "Directories created via container, files via bind-mount (hot-reload OK)."
