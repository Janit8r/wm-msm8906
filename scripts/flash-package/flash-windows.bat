@echo off
setlocal enabledelayedexpansion
chcp 936 >nul
cd /d "%~dp0"
title WF2 OpenWrt 一键刷机

echo ============================================================
echo   WF2 / UFI-W-001 (QRZL903, msm8916)  OpenWrt 一键刷机
echo   适用于「Android 原厂系统」的设备
echo ============================================================
echo.
echo 这个脚本会做这些事：
echo   1. 把设备切到 fastboot，刷入 lk2nd 临时引导
echo   2. 备份 modem 校准分区 fsc / fsg / modemst1 / modemst2
echo   3. 重写分区表（原厂 GPT 和 OpenWrt 的布局完全不同）
echo   4. 刷入新的 bootloader
echo   5. 把校准分区写回新位置（不做这步刷完没信号）
echo   6. 刷入 boot.img / rootfs.img
echo.
echo [警告] 会清空设备上的原厂 Android 和所有数据，不可恢复。
echo.
choice /c YN /m "确认继续"
if errorlevel 2 goto :cancel
echo.

REM ---------- 0. 检查文件 ----------
set MISSING=0
for %%f in (adb.exe fastboot.exe AdbWinApi.dll AdbWinUsbApi.dll boot.img rootfs.img lk2nd.img gpt_both0-fixed.bin aboot.bin hyp.mbn rpm.mbn sbl1.mbn tz.mbn sbc_1.0_8016.bin) do (
    if not exist "%%f" (
        echo [错误] 缺少文件: %%f
        set MISSING=1
    )
)
if "%MISSING%"=="1" (
    echo.
    echo 请确认压缩包已完整解压，且在本目录下运行本脚本。
    goto :fail
)

echo [1/6] 切换到 fastboot 模式
adb get-state >nul 2>&1
if not errorlevel 1 (
    echo       检测到 Android 设备，正在重启到 fastboot ...
    adb reboot bootloader
) else (
    echo       没有检测到 adb 设备。
    echo       如果设备屏幕已经显示 FASTBOOT，可以直接继续；
    echo       如果设备还在 Android 里，请先打开「USB 调试」再重跑本脚本。
)
call :wait_fastboot 90
if errorlevel 1 (
    echo       [错误] 90 秒内没有检测到 fastboot 设备。
    echo              设备没进 fastboot 的话，先试 `adb reboot bootloader`，
    echo              或者按住按键开机进 fastboot；再不行用 QFIL/EDL 方案。
    goto :fail
)
echo       OK
echo.

echo [2/6] 刷入 lk2nd 临时引导并重启
fastboot erase boot >nul 2>&1
fastboot flash boot lk2nd.img
if errorlevel 1 goto :fail_flash
fastboot reboot
echo       等待设备重新进入 fastboot ...
call :wait_fastboot 120
if errorlevel 1 (
    echo       [错误] lk2nd 启动后没有回到 fastboot。
    goto :fail
)
echo       OK
echo.

echo [3/6] 备份 modem 校准分区（很重要，别跳过）
call :dump fsc
if errorlevel 1 goto :fail_dump
call :dump fsg
if errorlevel 1 goto :fail_dump
call :dump modemst1
if errorlevel 1 goto :fail_dump
call :dump modemst2
if errorlevel 1 goto :fail_dump
echo       OK：fsc.bin / fsg.bin / modemst1.bin / modemst2.bin 已保存
echo       建议把这 4 个文件复制出来单独存一份。
echo.

echo [4/6] 重写分区表并刷入 bootloader
REM 原厂 GPT 里没有 lk2nd 分区，这条会报错，属正常，忽略即可
fastboot erase lk2nd >nul 2>&1
fastboot erase boot >nul 2>&1
fastboot reboot bootloader >nul 2>&1
call :wait_fastboot 90
if errorlevel 1 (
    echo       [错误] 重新进入 bootloader 失败。
    goto :fail
)
call :fb flash partition gpt_both0-fixed.bin
if errorlevel 1 goto :fail_flash
call :fb flash hyp hyp.mbn
if errorlevel 1 goto :fail_flash
call :fb flash rpm rpm.mbn
if errorlevel 1 goto :fail_flash
call :fb flash sbl1 sbl1.mbn
if errorlevel 1 goto :fail_flash
call :fb flash tz tz.mbn
if errorlevel 1 goto :fail_flash
call :fb flash aboot aboot.bin
if errorlevel 1 goto :fail_flash
call :fb flash cdt sbc_1.0_8016.bin
if errorlevel 1 goto :fail_flash
echo       OK
echo.

echo [5/6] 回填校准分区（顺序必须在重写 GPT 之后）
call :fb flash fsc fsc.bin
if errorlevel 1 goto :fail_flash
call :fb flash fsg fsg.bin
if errorlevel 1 goto :fail_flash
call :fb flash modemst1 modemst1.bin
if errorlevel 1 goto :fail_flash
call :fb flash modemst2 modemst2.bin
if errorlevel 1 goto :fail_flash
echo       OK
echo.

echo [6/6] 刷入 OpenWrt 镜像
fastboot erase boot
fastboot erase rootfs
fastboot erase rootfs_data
fastboot reboot bootloader
call :wait_fastboot 90
if errorlevel 1 (
    echo       [错误] 重新进入 bootloader 失败。
    goto :fail
)
call :fb flash boot boot.img
if errorlevel 1 goto :fail_flash
call :fb flash rootfs rootfs.img
if errorlevel 1 goto :fail_flash
echo       OK
echo.

echo 全部完成，正在重启到 OpenWrt ...
fastboot reboot
echo.
echo 首次开机需要 1~3 分钟（会自动格式化 rootfs_data、生成 SSH 密钥、拉起 modem）。
echo 之后：
echo   WiFi  SSID  ImmortalWrt   无密码
echo   网口  http://192.168.10.1  （默认无密码）
echo   USB   adb shell 可直接登录
echo.
echo 如果 modem 起不来，等 3 分钟再看；日志用 logread -e auto-apn 查看。
echo.
pause
exit /b 0


REM ============ 子过程 ============

:wait_fastboot
set /a __n=0
:wait_fastboot_loop
fastboot devices 2>nul | findstr /r /c:"fastboot" >nul
if not errorlevel 1 exit /b 0
set /a __n+=1
if !__n! geq %1 exit /b 1
timeout /t 1 /nobreak >nul
goto :wait_fastboot_loop

:dump
echo       备份 %1 ...
fastboot oem dump %1 >nul 2>&1
if errorlevel 1 (
    echo       [错误] 设备不支持 fastboot oem dump %1
    echo              没有校准分区备份就重写 GPT，刷完会没有信号。
    echo              已中止，设备未被修改。
    exit /b 1
)
fastboot get_staged %1.bin >nul 2>&1
if errorlevel 1 (
    echo       [错误] 读取 %1 失败
    exit /b 1
)
if not exist "%1.bin" (
    echo       [错误] 没有生成 %1.bin
    exit /b 1
)
exit /b 0

:fb
fastboot %* 
if errorlevel 1 (
    echo       [错误] fastboot %* 失败
    exit /b 1
)
exit /b 0

:cancel
echo 已取消。
exit /b 0

:fail_dump
echo.
echo [中止] 校准分区没有备份成功，为了不把设备刷成没信号，脚本已停止。
echo        设备当前状态：还在 lk2nd 的 fastboot 里，原厂系统未改动。
echo        你可以直接断电重启，会回到原厂 Android。
goto :fail

:fail_flash
echo.
echo [中止] fastboot 命令失败。
echo        常见原因：bootloader 未解锁（fastboot 会提示 not allowed）。
echo        如果 GPT 已经重写，设备会无法启动原厂系统，
echo        请重新执行本脚本（校准分区备份文件还在本目录，不会丢）。
goto :fail

:fail
echo.
pause
exit /b 1
