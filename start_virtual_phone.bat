@echo off
title DanieWatch Virtual Phone
echo ==========================================================
echo   Starting DanieWatch Virtual Mobile (Auto DirectX/OpenGL)
echo   Please keep this window open while testing your app.
echo ==========================================================
"E:\AndroidSDK\emulator\emulator.exe" -avd DanieWatch_Preview -gpu auto -no-boot-anim -accel on
