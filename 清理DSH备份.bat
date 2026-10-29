@echo off
chcp 65001 >nul
title DSH 备份清理工具
color 0B

echo ========================================
echo         DSH 备份清理工具
echo ========================================
echo.
echo 正在扫描备份文件夹...
echo (目标目录: %USERPROFILE%\.dsh\profiles\desktop)
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$path = Join-Path $env:USERPROFILE '.dsh\profiles\desktop';" ^
  "$backups = @(Get-ChildItem -Path $path -Filter '.force-install-backup-*' -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending);" ^
  "if ($backups.Count -eq 0) { Write-Host '没有找到任何备份。' -ForegroundColor Yellow; exit 0 };" ^
  "$keep = @($backups | Select-Object -First 5);" ^
  "$keepSize = if ($keep.Count -gt 0) { [math]::Round((($keep | ForEach-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }) | Measure-Object -Sum).Sum / 1MB, 2) } else { 0 };" ^
  "Write-Host ('当前备份总数: ' + $backups.Count + '，将保留最新 5 个（合计约 ' + $keepSize + ' MB）') -ForegroundColor Cyan;" ^
  "if ($backups.Count -gt 5) {" ^
  "    $toDelete = @($backups | Select-Object -Skip 5);" ^
  "    $delSize = [math]::Round((($toDelete | ForEach-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }) | Measure-Object -Sum).Sum / 1MB, 2);" ^
  "    $toDelete | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue;" ^
  "    Write-Host ('清理完成！已删除 ' + $toDelete.Count + ' 个旧备份（释放约 ' + $delSize + ' MB）。') -ForegroundColor Green" ^
  "} else {" ^
  "    Write-Host '当前备份数量不足 5 个，无需清理。' -ForegroundColor Yellow" ^
  "}"

echo.
echo ========================================
echo 脚本执行结束。
pause