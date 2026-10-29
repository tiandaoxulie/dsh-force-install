# dsh-force-install
DeepSeek Harness插件的强制安装工具.基于 pnpm 解决 already-installed 等,支持指定版本,目录自动探测及备份回滚.
# DSH 强制安装器 (Force Installer) 使用说明

## 🎯 这是什么？

这是一个用于绕过 DSH 官方插件安装限制的“底层物理安装工具”。
当你在 DSH 界面里点击“安装/更新”遇到以下问题时，它就是你的终极解药：

- 报错 {"code":"already-installed"}（死活不让覆盖安装）
- 报错 [ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION]（被 pnpm 供应链安全策略拦截）
- 插件在市场中莫名丢失，或者市场自身损坏无法打开
- 你想安装一个不在插件市场里的野生 npm 插件
- 你想强制降级/升级到某个特定版本

## 📁 文件清单

把以下文件放在同一个文件夹里：

  dsh-force-install.cmd     ← 双击这个启动（主入口）
  dsh-force-install.ps1     ← 核心逻辑，不要单独双击它
  清理DSH备份.bat           ← 可选，备份清理工具

## 🚀 快速上手（3 步）

1. 双击运行 dsh-force-install.cmd
2. 在黑框里输入插件名，回车
3. 如果 DSH 正在运行，脚本会问是否自动关闭，输入 Y 回车
   然后坐等它自动完成：备份 → 强制拉取 → 校验 → 重启 DSH

### 插件名怎么输入

| 你想做的事              | 输入示例                             |
|------------------------|--------------------------------------|
| 装最新版                | dsh-codex-effort-slider              |
| 装指定版本              | dsh-codex-effort-slider@1.1.3        |
| 装带组织前缀的包        | @myorg/my-plugin@2.0.0               |
| 装完检查下会发生什么    | 上面任意一个，然后在“是否只预览”时输 y |

## 👀 先预览，再执行（推荐新手用）

启动后会问：“是否只预览命令、不实际安装？(y/N)”

- 输入 y → 只打印“将要执行的命令”和“将启动的 exe 路径”，不碰任何文件
- 输入 N 或直接回车 → 正常执行

这个功能在两种情况下特别有用：

- 你不确定脚本会不会装错地方（先看预览里显示的目标路径对不对）
- 你想把命令复制给别人看

## 📍 安装目录自动探测

脚本不再写死 C 盘，会按以下优先级自动找到 DSH 装在哪里：

  1. 手动指定（参数 -AppRoot 或环境变量 DSH_INSTALL_ROOT）
  2. 正在运行的 DSH 进程（最可靠：当前真正在跑的）
  3. App Paths 注册表（Electron 安装器最常注册的位置）
  4. Uninstall 注册表（InstallLocation / DisplayIcon / UninstallString）
  5. 默认路径（LOCALAPPDATA / ProgramFiles / ProgramFiles x86）

每个候选路径都会验证“DeepSeek Harness.exe 是否真实存在”，
死路径（注册表残留）会被自动跳过，不会误用。

启动时你会看到类似这样的输出，说明探测成功：

  DSH 安装目录: D:\Apps\DeepSeek Harness
  探测来源: 运行中进程

### 如果自动探测失败怎么办？

极少数情况（绿色版、便携版、目录被手动改名）会探测不到。
脚本会明确告诉你“请手动指定”，这时用下面任一种方式：

方式 A —— 环境变量（推荐，一次设置永久生效）
  在 cmd 里执行：
    setx DSH_INSTALL_ROOT "D:\你的实际安装目录"
  然后重新双击 dsh-force-install.cmd

方式 B —— 临时设置
  在 cmd 里执行：
    set DSH_INSTALL_ROOT=D:\你的实际安装目录
    dsh-force-install.cmd

方式 C —— 直接用 PowerShell 调用
  powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-force-install.ps1 ^
      -TargetPackage dsh-codex-effort-slider ^
      -AppRoot "D:\你的实际安装目录"

## 🧹 附加工具：备份清理器

每次强制安装都会在 profile 目录生成一个 .force-install-backup-时间戳 文件夹。
时间久了会占空间。

- 双击运行 清理DSH备份.bat
- 工具会自动扫描、统计大小、保留最新 5 个，删除更旧的
- 运行时会显示：“当前备份总数 X，将保留最新 5 个（合计约 Y MB）”
- 删除后告诉你：“已删除 N 个旧备份（释放约 M MB）”

## 🆘 出问题了怎么回滚

每次安装前，脚本都会在 profile 目录下生成一个备份文件夹。
如果装完发现环境坏了，按下面步骤回滚：

1. 完全退出 DSH（含托盘图标）
2. 打开 profile 目录（默认 %USERPROFILE%\.dsh\profiles\desktop）
3. 找到最新的 .force-install-backup-时间戳 文件夹
4. 把里面的 package.json、pnpm-lock.yaml、pnpm-workspace.yaml
   复制回 profile 目录（覆盖）
5. 在 profile 目录执行：pnpm install --frozen-lockfile
6. 重新启动 DSH

每个备份文件夹里都有一份 restore.txt，内容就是上面这些步骤，
到时候直接打开照着做即可，不用回来翻这份说明。

## ⚠️ 注意事项

### 安装到哪个环境
脚本默认强制安装到 desktop（桌面端）环境。
如果你需要装到 Web 端，用记事本打开 dsh-force-install.ps1，
把第一行参数里的 profiles\desktop 改成 profiles\web 即可。

### 防乱码黑科技
.cmd 启动器里做了强制 UTF-8 读取。
只要你用记事本另存为 UTF-8 编码保存，修改代码也不会乱码。
（不要存成 ANSI，会乱码。）

### 版本对比什么时候会提示“期望 X，实际 Y”
只有输入精确版本号（如 1.2.3）时才会对比。
输入 latest、^1.0.0、~2.3.0、>=1.0.0 这类范围表达式时不会误报。
提示里如果出现版本不一致，说明 pnpm 没真正换包（可能是缓存了旧版），
先手动删除 node_modules\对应包名 目录，再重跑一次。

### DSH 升级后如果脚本突然不工作了
最可能的原因：DSH 内部的 pnpm 路径变了。
原路径是：
  <安装目录>\resources\runtime\primary-runtime\dependencies\pnpm\bin\pnpm.cjs

如果找不到 pnpm，报错信息里会附带排查指引。
你手动打开 <安装目录>\resources\runtime 看看实际结构，
反馈给脚本维护者更新路径即可。

### “安装失败（退出码 X）”
最常见的是 lockfile 冲突。解决办法：
  在 profile 目录执行：pnpm clean --lockfile
  然后重跑 dsh-force-install.cmd

## 🎁 进阶：直接调用 .ps1（给喜欢折腾的人）

基本用法：

  powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-force-install.ps1 ^
      -TargetPackage <包名> [-AppRoot <目录>] [-DryRun] [-NoRestart] [-NoQuit]

参数说明：

  -TargetPackage   要装的包名（必填，scoped 包要用单引号包住）
  -ProfileDir      装到哪个 profile（默认 desktop，可改成 web）
  -AppRoot         手动指定 DSH 安装目录
  -DryRun          只预览，不执行
  -NoRestart       装完不自动重启 DSH
  -NoQuit          检测到 DSH 在运行就直接报错退出，不提示自动关闭

示例：

  # 装到 Web 端 + 装完不重启
  powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-force-install.ps1 ^
      -TargetPackage dsh-codex-effort-slider ^
      -ProfileDir "$env:USERPROFILE\.dsh\profiles\web" ^
      -NoRestart

  # 只预览会做什么（不做任何修改）
  powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-force-install.ps1 ^
      -TargetPackage '@myorg/plugin@2.0.0' -DryRun

  # DSH 装在 D 盘 + 自动关闭后重装
  powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-force-install.ps1 ^
      -TargetPackage dsh-codex-effort-slider ^
      -AppRoot "D:\Apps\DeepSeek Harness"

注意：直接调用 .ps1 时，scoped 包名必须用单引号包裹，
否则 PowerShell 会把 @ 当成特殊语法解析报错。
通过 .cmd 启动则无此限制（启动器用环境变量传参，绕过了命令行解析）。

## 💡 常见问题速查

Q: 装完提示“安装指令执行成功，但在 node_modules 里找不到 xxx”？
A: pnpm 可能缓存了旧版。删掉 node_modules\<包名> 目录再重跑一次。

Q: 提示“DSH 未能自动退出”？
A: 手动完全退出 DSH（含托盘图标）后重试。有时托盘里还藏着一个进程。

Q: 提示“找不到 profile 的 package.json”？
A: profile 目录不对。确认 <用户目录>\.dsh\profiles\desktop 下确实有 package.json。
   如果你之前没启动过 DSH 桌面端，先启动一次让它生成 profile。

Q: 能用这个工具装非市场的插件吗？
A: 可以，只要能通过 npm 拉到的包都能装。装完的插件不一定能在 DSH 界面里显示，
   这取决于插件本身的 manifest 声明。

Q: 卸载插件用这个脚本吗？
A: 不。这是“安装器”，不处理卸载。卸载请走 DSH 官方界面，
   或者手动 pnpm remove <包名>。
