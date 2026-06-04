# Compress poster images using ffmpeg
$posterDir = "c:\Users\mdani\Desktop\Daniewatch android app antigravity\poster"
$tempDir = "$posterDir\_temp"

# Create temp directory
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

$totalBefore = 0
$totalAfter = 0

Get-ChildItem -Path $posterDir -Filter "*.webp" | ForEach-Object {
    $input = $_.FullName
    $output = Join-Path $tempDir $_.Name
    $totalBefore += $_.Length
    
    Write-Host "Compressing: $($_.Name) ($([math]::Round($_.Length/1KB))KB)" -ForegroundColor Yellow
    
    # Resize to 400px width, quality 72
    & ffmpeg -y -i "$input" -vf "scale=400:-1" -q:v 72 "$output" 2>$null
    
    if (Test-Path $output) {
        $newSize = (Get-Item $output).Length
        $totalAfter += $newSize
        Write-Host "  -> $([math]::Round($newSize/1KB))KB (saved $([math]::Round(($_.Length - $newSize)/1KB))KB)" -ForegroundColor Green
    } else {
        Write-Host "  -> FAILED, keeping original" -ForegroundColor Red
        Copy-Item $input $output
        $totalAfter += $_.Length
    }
}

# Replace originals with compressed versions
Get-ChildItem -Path $tempDir -Filter "*.webp" | ForEach-Object {
    $dest = Join-Path $posterDir $_.Name
    Copy-Item $_.FullName $dest -Force
}

# Clean up temp dir
Remove-Item $tempDir -Recurse -Force

Write-Host ""
Write-Host "=== POSTER RESULTS ===" -ForegroundColor Cyan
Write-Host "Before: $([math]::Round($totalBefore/1MB, 2)) MB"
Write-Host "After:  $([math]::Round($totalAfter/1MB, 2)) MB"
Write-Host "Saved:  $([math]::Round(($totalBefore - $totalAfter)/1MB, 2)) MB"

# Compress google_logo.png -> smaller png
$googleLogo = "c:\Users\mdani\Desktop\Daniewatch android app antigravity\assets\google_logo.png"
$googleLogoTemp = "c:\Users\mdani\Desktop\Daniewatch android app antigravity\assets\google_logo_temp.png"
$beforeSize = (Get-Item $googleLogo).Length

Write-Host ""
Write-Host "Compressing google_logo.png ($([math]::Round($beforeSize/1KB))KB)..." -ForegroundColor Yellow
& ffmpeg -y -i "$googleLogo" -vf "scale=64:-1" "$googleLogoTemp" 2>$null
if (Test-Path $googleLogoTemp) {
    $afterSize = (Get-Item $googleLogoTemp).Length
    Move-Item $googleLogoTemp $googleLogo -Force
    Write-Host "  -> $([math]::Round($afterSize/1KB))KB (saved $([math]::Round(($beforeSize - $afterSize)/1KB))KB)" -ForegroundColor Green
}
