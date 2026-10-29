<#
  DSH 强制安装器 (DSH Force Installer)
  功能：绕过官方/市场的状态锁，强制安装或补装 DSH 插件。
  用法：优先通过 dsh-force-install.cmd 启动（会做引号防护与 UTF-8 读取）。
        也可直接：
        powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-force-install.ps1 -TargetPackage <包名> [-AppRoot <安装目录>] [-DryRun] [-NoRestart] [-NoQuit]

  注意：
  1. 直接调用本脚本时，scoped 包名请用单引号包裹：
     -TargetPackage '@scope/name@1.0.0'
     （通过 dsh-force-install.cmd 启动则无此限制）
  2. 安装目录会自动探测；探测失败时可显式指定：
     -AppRoot "D:\YourPath\DeepSeek Harness"
     或设置环境变量 DSH_INSTALL_ROOT。
#>

[CmdletBinding()]
param(
  [string]$ProfileDir = (Join-Path $env:USERPROFILE '.dsh\profiles\desktop'),
  [string]$TargetPackage = '',
  [string]$AppRoot = '',
  [switch]$NoQuit,
  [switch]$NoRestart,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Fail($msg) { Say $msg 'Red'; exit 1 }

# ============================================================
# 从各种来源收集候选安装目录（不验证，只收集；验证在最后统一做）
# ============================================================
function Get-DshInstallInfo {
    param([string]$ExplicitRoot)

    $candidates = New-Object System.Collections.Generic.List[object]
    $addCandidate = {
        param($src, $root)
        if ([string]::IsNullOrWhiteSpace($root)) { return }
        $trimmed = $root.Trim().Trim('"').TrimEnd('\')
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
        $candidates.Add([pscustomobject]@{ Source = $src; Root = $trimmed })
    }

    # 1) 显式参数 / 环境变量（最高优先级：便于调试与便携安装）
    if ($ExplicitRoot) { & $addCandidate '参数 -AppRoot' $ExplicitRoot }
    if ($env:DSH_INSTALL_ROOT) { & $addCandidate '环境变量 DSH_INSTALL_ROOT' $env:DSH_INSTALL_ROOT }

    # 2) 运行中的进程（最可靠：这正是当前真正在跑的）
    #    注意：$p.Path 在 ErrorActionPreference=Stop 下访问失败会抛异常，必须 try/catch
    foreach ($p in @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) {
        try {
            $pPath = $p.Path
            if (-not [string]::IsNullOrWhiteSpace($pPath)) {
                & $addCandidate '运行中进程' (Split-Path -LiteralPath $pPath -Parent)
            }
        } catch { }
    }

    # 3) App Paths 注册表（Electron 安装器最常注册的位置，比 Uninstall 精准）
    foreach ($hive in 'HKCU:', 'HKLM:') {
        $key = "$hive\Software\Microsoft\Windows\CurrentVersion\App Paths\DeepSeek Harness.exe"
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $v = $item.'(default)'
            if (-not [string]::IsNullOrWhiteSpace($v)) {
                $exePath = $v.Trim().Trim('"')
                & $addCandidate 'App Paths 注册表' (Split-Path -LiteralPath $exePath -Parent)
            }
        } catch { }
    }

    # 4) Uninstall 注册表：InstallLocation / DisplayIcon / UninstallString
    $uninstallRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($uRoot in $uninstallRoots) {
        $entries = @()
        try {
            $entries = @(Get-ItemProperty -Path "$uRoot\*" -ErrorAction SilentlyContinue |
                         Where-Object { $_.DisplayName -like '*DeepSeek Harness*' })
        } catch { continue }

        foreach ($e in $entries) {
            if ($e.InstallLocation) {
                & $addCandidate 'Uninstall 注册表 (InstallLocation)' $e.InstallLocation
            }
            # DisplayIcon 形如 "C:\...\app.exe,0"，UninstallString 形如 '"C:\...\Uninstall.exe" /S'
            foreach ($raw in @($e.DisplayIcon, $e.UninstallString)) {
                if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                $s = $raw.Trim()
                # 去掉 MSI 风格尾部的 ",0" / ",-1"
                if ($s -match '^(.+?),\s*-?\d+$') { $s = $matches[1].Trim() }
                if ($s.StartsWith('"') -and $s.IndexOf('"', 1) -gt 0) {
                    $s = $s.Substring(1, $s.IndexOf('"', 1) - 1)
                } elseif ($s -match '^(.*?\.exe)(\s|$)') {
                    $s = $matches[1]
                }
                try {
                    & $addCandidate 'Uninstall 注册表 (UninstallString/DisplayIcon)' (Split-Path -LiteralPath $s -Parent)
                } catch { }
            }
        }
    }

    # 5) 常见默认路径兜底
    if ($env:LOCALAPPDATA)       { & $addCandidate '默认路径 (LOCALAPPDATA)'       (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness') }
    if ($env:ProgramFiles)       { & $addCandidate '默认路径 (ProgramFiles)'       (Join-Path $env:ProgramFiles 'DeepSeek Harness') }
    if (${env:ProgramFiles(x86)}) { & $addCandidate '默认路径 (ProgramFiles x86)'  (Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness') }

    # 逐个验证 exe 真实存在才采纳
    foreach ($c in $candidates) {
        $exe = Join-Path $c.Root 'DeepSeek Harness.exe'
        if (Test-Path -LiteralPath $exe) {
            return [pscustomobject]@{
                Root   = $c.Root
                Exe    = $exe
                Source = $c.Source
            }
        }
    }
    return $null
}

# ---------- 0. 参数校验与解析 ----------
Say '========================================' 'Cyan'
Say '         DSH 强制安装器 (Force Installer)' 'Cyan'
Say '========================================' 'Cyan'
Say "目标环境: $ProfileDir"

if ([string]::IsNullOrWhiteSpace($TargetPackage)) { Fail '错误：未指定插件名。' }
$TargetPackage = $TargetPackage.Trim()

# 解析包名与版本，兼容 scoped 包 @scope/name@version
# [修复3] 尾部空版本 "foo@" 归一化为 "foo"，避免 pnpm 报 Invalid package name
$pureName = $TargetPackage
$wantVersion = $null
if ($TargetPackage.StartsWith('@')) {
    $atIdx = $TargetPackage.IndexOf('@', 1)
    if ($atIdx -gt 0) {
        $pureName = $TargetPackage.Substring(0, $atIdx)
        $wantVersion = $TargetPackage.Substring($atIdx + 1)
        if ([string]::IsNullOrEmpty($wantVersion)) { $wantVersion = $null; $TargetPackage = $pureName }
    }
} else {
    $atIdx = $TargetPackage.IndexOf('@')
    if ($atIdx -gt 0) {
        $pureName = $TargetPackage.Substring(0, $atIdx)
        $wantVersion = $TargetPackage.Substring($atIdx + 1)
        if ([string]::IsNullOrEmpty($wantVersion)) { $wantVersion = $null; $TargetPackage = $pureName }
    }
}
Say "目标插件: $TargetPackage"
Say "解析结果: 包名=$pureName, 版本=$(if ($wantVersion) { $wantVersion } else { 'latest' })"

# ---------- 0.5 自动探测 DSH 安装路径 ----------
$installInfo = Get-DshInstallInfo -ExplicitRoot $AppRoot
if (-not $installInfo) {
    Fail @"
错误：未能自动定位 DSH 安装目录（找不到 'DeepSeek Harness.exe'）。
已尝试：参数 -AppRoot → 环境变量 DSH_INSTALL_ROOT → 运行中进程
        → App Paths 注册表 → Uninstall 注册表 → 默认路径。

请手动指定安装目录后重试，例如：
  方式一（CMD 启动器）：先 set DSH_INSTALL_ROOT=D:\你的安装路径，再双击 cmd
  方式二（直接调用 PS）：powershell -File .\dsh-force-install.ps1 -TargetPackage foo -AppRoot "D:\你的安装路径"
"@
}
$AppRoot = $installInfo.Root
$AppExe  = $installInfo.Exe
$PnpmCjs = Join-Path $AppRoot 'resources\runtime\primary-runtime\dependencies\pnpm\bin\pnpm.cjs'
Say "DSH 安装目录: $AppRoot" 'DarkGray'
Say "探测来源: $($installInfo.Source)" 'DarkGray'
Say ''

if (-not (Test-Path (Join-Path $ProfileDir 'package.json'))) { Fail "找不到 profile 的 package.json：$ProfileDir" }

# ---------- 1. 选择 node 与 pnpm（只读检查，不改动任何东西） ----------
$nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
$node = if ($nodeCmd) { $nodeCmd.Source } else { $null }
$usingElectronAsNode = $false
if (-not $node) {
    $node = $AppExe
    $usingElectronAsNode = $true
    Say '未找到独立 node，将使用 DSH 自带运行时执行。' 'DarkGray'
}
if (-not (Test-Path $PnpmCjs)) {
    Fail @"
找不到 pnpm：$PnpmCjs

可能原因：
  1. DSH 版本升级后内部目录结构变化（原路径：resources\runtime\primary-runtime\dependencies\pnpm\bin\pnpm.cjs）
  2. 探测到的安装目录不完整

排查建议：手动打开 "$AppRoot\resources\runtime"，看看 pnpm 的实际位置，
然后反馈给脚本维护者更新路径。
"@
}

# 打印 pnpm 版本：未来 DSH 升级后如果参数/路径变了，这行能帮你第一时间定位
if ($usingElectronAsNode) { $env:ELECTRON_RUN_AS_NODE = '1' }
try {
    $pnpmVer = & $node $PnpmCjs --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $pnpmVer) { Say "pnpm 版本: $pnpmVer" 'DarkGray' }
} catch {
    Say '警告：无法读取 pnpm 版本（不影响安装，但可能意味着运行时结构有变化）。' 'Yellow'
} finally {
    Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
}

# ---------- 2. DryRun：只预览，不修改任何东西 ----------
# [修复1] PowerShell 双引号内不用 \" 转义，改用 -f 格式化，避免解析崩溃
if ($DryRun) {
    Say '' 'Cyan'
    Say '===== DryRun 模式：仅预览，不实际执行 =====' 'Cyan'
    Say "工作目录: $ProfileDir"
    if ($usingElectronAsNode) {
        Say ('将执行: ELECTRON_RUN_AS_NODE=1 "{0}" "{1}" add {2} --config.minimum-release-age=0' -f $node, $PnpmCjs, $TargetPackage) 'White'
    } else {
        Say ('将执行: "{0}" "{1}" add {2} --config.minimum-release-age=0' -f $node, $PnpmCjs, $TargetPackage) 'White'
    }
    if (-not $NoRestart) { Say "完成后将启动: $AppExe" 'White' }
    Say ''
    Say 'DryRun 结束，未做任何修改。' 'Green'
    exit 0
}

# ---------- 3. 要求 DSH 完全退出 ----------
function Get-DshProcesses { @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) }

$procs = Get-DshProcesses
if ($procs.Count -gt 0) {
  if ($NoQuit) { Fail "DSH 仍在运行（$($procs.Count) 个进程）。请完全退出后重试。" }
  Say "检测到 DSH 正在运行（$($procs.Count) 个进程）。" 'Yellow'
  Say '强制安装需要完全退出 DSH，否则底层 pnpm 无法替换正在使用的文件。' 'Yellow'
  $answer = Read-Host '现在自动关闭 DSH 吗？请先保存好正在输入的内容 (Y/N)'
  if ($answer -notmatch '^[Yy]') { Fail '已取消：请手动完全退出 DSH（含托盘图标）后重新运行。' }

  Say '正在请求 DSH 正常关闭（忽略报错强杀）...'
  $procs | Stop-Process -Force -ErrorAction SilentlyContinue

  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-DshProcesses).Count -gt 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }

  if ((Get-DshProcesses).Count -gt 0) { Fail 'DSH 未能自动退出，请手动退出后重试。' }
  Say 'DSH 已退出。' 'Green'
} else {
  Say 'DSH 未运行，准备就绪。' 'Green'
}

# ---------- 4. 备份 + 回滚说明 ----------
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $ProfileDir ".force-install-backup-$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
foreach ($f in 'package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml') {
  $src = Join-Path $ProfileDir $f
  if (Test-Path $src) { Copy-Item $src (Join-Path $backup $f) }
}
$restoreTxt = @"
如需回滚，请按以下步骤操作：
1. 完全退出 DSH（含托盘图标）
2. 将本备份文件夹中的以下文件复制回 profile 目录（覆盖）：
   - package.json
   - pnpm-lock.yaml
   - pnpm-workspace.yaml（如果存在）
3. 在 profile 目录中执行：
   pnpm install --frozen-lockfile
4. 重新启动 DSH

profile 目录: $ProfileDir
备份时间: $stamp
备份来源: DSH 强制安装器
"@
Set-Content -LiteralPath (Join-Path $backup 'restore.txt') -Value $restoreTxt -Encoding UTF8
Say "已备份当前配置到: $backup"

# ---------- 5. 执行强制安装 ----------
Say ''
Say '正在执行强制安装（已附加 --config.minimum-release-age=0 绕过供应链闸门）...' 'Cyan'
Push-Location $ProfileDir
$code = 1
try {
  if ($usingElectronAsNode) { $env:ELECTRON_RUN_AS_NODE = '1' }
  & $node $PnpmCjs add $TargetPackage --config.minimum-release-age=0
  $code = $LASTEXITCODE
} finally {
  Pop-Location
  Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
}

if ($code -ne 0) {
  Say ''
  Say "安装失败（退出码 $code）。备份位于：$backup" 'Red'
  Say '如果提示 lockfile 报错，请手动去 profile 目录执行 pnpm clean --lockfile 后再试。' 'Yellow'
  Fail '未完成安装。'
}

# ---------- 6. 验证安装结果（含 scoped 路径与版本对比） ----------
# [修复2] 只有精确版本号（x.y.z）才做版本对比；latest / ^ / ~ / >= 等范围表达式不误报
$pureNamePath = $pureName -replace '/', '\'
$pluginPkgPath = Join-Path $ProfileDir "node_modules\$pureNamePath\package.json"

if (Test-Path $pluginPkgPath) {
    $installed = Get-Content -LiteralPath $pluginPkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $installedName = if ($installed.name) { $installed.name } else { $pureName }
    Say ''
    Say "验证通过：已安装 $installedName@$($installed.version)" 'Green'

    $isExactVersion = $wantVersion -and ($wantVersion -match '^\d+\.\d+\.\d+([\-\+].*)?$')
    if ($isExactVersion -and $installed.version -ne $wantVersion) {
        Say "注意：期望版本 $wantVersion，实际落地 $($installed.version)。" 'Yellow'
        Say '如需强制换版本，请先手动删除 node_modules 下对应目录后重试。' 'Yellow'
    }
} else {
    Fail "安装指令执行成功，但在 node_modules 里找不到 $pureName（查找路径：$pluginPkgPath），请手动检查。"
}

# ---------- 7. 重新启动 ----------
if (-not $NoRestart) {
  Say '正在重新启动 DSH...'
  Start-Process -FilePath $AppExe | Out-Null
} else {
  Say '已跳过自动重启（-NoRestart）。' 'DarkGray'
}

Say ''
Say '强制安装流程全部完成！' 'Green'
exit 0