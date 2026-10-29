@echo off
chcp 65001 >nul
title DSH 强制安装器
color 0B
setlocal EnableExtensions
set "PLUGIN_NAME="
set "DRYRUN_CHOICE="
set "DRYRUN_BOOL="
set "DshPluginName="
set "DshDryRun="
set "PS_EXIT="

echo ========================================
echo         DSH 强制安装器
echo ========================================
echo.
echo 提示：直接输入插件名即可。如果需要特定版本，请用 名字@版本号。
echo 例如：dsh-codex-effort-slider
echo 支持 scoped 包：@scope/name@1.2.3
echo.
set /p PLUGIN_NAME="请输入要安装的插件名: "

if not defined PLUGIN_NAME (
    echo.
    echo 错误：插件名不能为空！
    pause
    exit /b 1
)

set /p DRYRUN_CHOICE="是否只预览命令、不实际安装？(y/N): "
if /i "%DRYRUN_CHOICE%"=="y" (set "DRYRUN_BOOL=True") else (set "DRYRUN_BOOL=False")

:: 通过环境变量把包名交给 PowerShell，避免任何命令行解析/注入问题
set "DshPluginName=%PLUGIN_NAME%"
set "DshDryRun=%DRYRUN_BOOL%"

echo.
echo ----------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $content = Get-Content -LiteralPath '%~dp0dsh-force-install.ps1' -Raw -Encoding UTF8; $sb = [ScriptBlock]::Create($content); & $sb -TargetPackage $env:DshPluginName -DryRun:$($env:DshDryRun -eq 'True') }"

set "PS_EXIT=%ERRORLEVEL%"
echo.
echo ----------------------------------------
if "%PS_EXIT%"=="0" (
    echo [成功] 脚本执行结束。
) else (
    echo [失败] 安装未完成，请查看上方输出。
)
pause