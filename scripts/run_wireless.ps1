# DanieWatch Wireless Live Preview Auto-Connector
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "    DanieWatch - Permanent Wireless Live Preview       " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$fixedIp = "192.168.100.78"
$fixedPort = "5555"
$target = "$fixedIp`:$fixedPort"

Write-Host "[1/3] Connecting to phone wirelessly at $target..." -ForegroundColor Yellow
& adb connect $target

$devices = & adb devices
Write-Host $devices

if ($devices -match "$fixedIp`:$fixedPort\s+device") {
    Write-Host "[2/3] Successfully connected to phone wirelessly!" -ForegroundColor Green
} else {
    Write-Host "[!] Checking for alternative wireless ports via mDNS..." -ForegroundColor Yellow
    $mdns = & adb mdns services
    Write-Host $mdns
}

Write-Host "[3/3] Launching Flutter live preview with .dart_define.env..." -ForegroundColor Cyan
& flutter run -d $target --dart-define-from-file=.dart_define.env
