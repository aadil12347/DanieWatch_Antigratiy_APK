@echo off
title DanieWatch Wireless Live Preview
color 0A
echo ========================================================
echo    DanieWatch - One-Click Wireless Live Preview
echo ========================================================
echo.
echo [1/3] Ensuring ADB server is active...
adb start-server

echo [2/3] Connecting to Phone at 192.168.100.78:5555...
adb connect 192.168.100.78:5555
adb devices

echo.
echo [3/3] Starting Flutter Live Preview with .dart_define.env...
flutter run -d 192.168.100.78:5555 --dart-define-from-file=.dart_define.env

pause
