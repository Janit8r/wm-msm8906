@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
cd /d "%~dp0"
title WF2 EDL 校准分区备份

echo ============================================================
echo   WF2  modem 校准分区备份（EDL / 9008 模式，只读，不改设备）
echo ============================================================
echo.
echo 用途：刷机前把 modem 的 NV 校准数据单独存一份，万一刷坏了能救回来。
echo 本脚本只做读取，不会写入任何东西。
echo.
echo 前提：设备已进入 9008 模式。可以执行 adb reboot edl，
echo       或者按住按键开机 / 短接测试点。
echo.

if not exist "emmcdl.exe" goto :no_tool
if not exist "prog_emmc_firehose_8916.mbn" goto :no_tool

echo 先试着用 adb 把设备切到 9008 ...
adb get-state >nul 2>&1
if not errorlevel 1 (
    adb reboot edl
    echo 已发送 reboot edl，等 5 秒 ...
    timeout /t 5 /nobreak >nul
) else (
    echo 没有 adb 设备，请手动让设备进入 9008 模式。
)
echo.
echo 打开「设备管理器」，在端口(COM 和 LPT) 下面找到
echo   Qualcomm HS-USB QDLoader 9008 (COMx)
echo 把那个 x 填进来。
echo.
set /p PORT=请输入 COM 端口号（只填数字，例如 6）:
if "%PORT%"=="" goto :cancel

set OUT=cal-backup
if not exist "%OUT%" mkdir "%OUT%"

echo.
echo 读取原厂分区表 ...
emmcdl.exe -p COM%PORT% -f prog_emmc_firehose_8916.mbn -MemoryName emmc -d 0 34 -o "%OUT%\gpt_stock.bin"
if errorlevel 1 goto :fail

echo.
echo 备份 fsc / fsg / modemst1 / modemst2 ...
emmcdl.exe -p COM%PORT% -f prog_emmc_firehose_8916.mbn -MemoryName emmc -d 284672 2    -o "%OUT%\fsc.bin"
if errorlevel 1 goto :fail
emmcdl.exe -p COM%PORT% -f prog_emmc_firehose_8916.mbn -MemoryName emmc -d 393280 3072 -o "%OUT%\fsg.bin"
if errorlevel 1 goto :fail
emmcdl.exe -p COM%PORT% -f prog_emmc_firehose_8916.mbn -MemoryName emmc -d 276480 3072 -o "%OUT%\modemst1.bin"
if errorlevel 1 goto :fail
emmcdl.exe -p COM%PORT% -f prog_emmc_firehose_8916.mbn -MemoryName emmc -d 279552 3072 -o "%OUT%\modemst2.bin"
if errorlevel 1 goto :fail

echo.
echo 备份完成，文件在 %OUT% 目录：
dir /b "%OUT%"
echo.
echo 这些文件是原厂 Android 的分区布局下的偏移量（只能在原厂系统上读）。
echo 请连同 gpt_stock.bin 一起保存。
echo 恢复方法（设备变砖时，把 COM6 换成实际端口）：
echo   emmcdl.exe -p COM6 -f prog_emmc_firehose_8916.mbn -MemoryName emmc -w modemst1 -o "%OUT%\modemst1.bin"
echo.
pause
exit /b 0

:no_tool
echo [错误] 缺少 emmcdl.exe 或 prog_emmc_firehose_8916.mbn
pause
exit /b 1

:cancel
echo 已取消。
exit /b 0

:fail
echo.
echo [错误] 读取失败。常见原因：
echo   - COM 口号填错
echo   - 设备不在 9008 模式
echo   - 有别的工具（QFIL / miko / 官方助手）占着串口，先关掉它们
pause
exit /b 1
