# Codex 工作状态悬浮窗

一个仅适用于 Windows 的 Codex 桌面悬浮小工具。它通过读取本机 Codex 会话记录显示各个对话的工作状态，同时展示 5 小时额度、一周额度以及可用重置次数。

## 功能

### 多对话状态灯

悬浮窗会为每个正在活动的顶层 Codex 对话显示一个状态灯，子代理和后台辅助会话不会单独占用状态灯：

- **红色**：Codex 正在思考、生成回复或执行工具。
- **蓝色**：需要用户操作，例如批准权限、选择方案、确认计划或回答问题。
- **乳白色**：对话已经完成或当前没有活动对话。刚完成的对话会保留约 5 秒的乳白色状态灯，然后从灯组中移除；所有对话均空闲时保留一个乳白色状态灯。
- **灰色**：没有检测到可用的本地 Codex 会话记录。

多个对话同时工作时会同时显示多个灯，灯的位置按对话保持稳定。对话数量较多时，状态灯会自动缩小以适应固定宽度的窗口。

### 额度与重置次数

状态灯右侧依次显示：

- **5h**：5 小时额度的剩余百分比，下方显示本地时间格式的重置时刻。
- **周**：一周额度的剩余百分比，下方显示重置日期。
- **可用重置次数**：当前账户可用的重置次数，并显示最近一至两个过期日期。

悬浮窗工作或等待用户操作时，5 小时和一周额度会跟随本地会话事件约每 10 秒更新一次；即使所有对话均处于空闲状态，也会每 5 分钟主动读取一次账户额度并刷新显示。可用重置次数和过期日期在工作时约每 60 秒查询一次，空闲时每 5 分钟查询一次。没有取得相应数据时，字段显示为 `--`。

### 窗口操作

- 启动后默认显示在桌面右下角，并保持置顶。
- 按住鼠标左键拖动可调整位置。
- 单击鼠标右键可切换是否置顶。
- 双击悬浮窗可关闭。
- 同一时间只允许运行一个实例；重复启动会将已有窗口移回主屏右下角并置顶，不会叠加多个窗口。
- 窗口不显示在任务栏中，也没有单独的关闭按钮或鼠标悬停提示。

## 使用方法

### 直接启动

双击 `Start-CodexStatusWidget.vbs`。启动器会在后台调用 Windows PowerShell，因此不会额外显示控制台窗口。

### 创建桌面快捷方式

在 Windows PowerShell 中进入项目目录，然后运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-DesktopShortcut.ps1
```

脚本会在当前用户桌面创建“Codex 状态灯”快捷方式，并使用 `assets` 目录中的图标。

## Windows 平台限制

本工具只支持 Windows，不支持 macOS 或 Linux。它没有对某个具体 Windows 版本作保证，但运行环境必须具备以下组件：

- 支持 WPF 的 Windows 桌面环境；悬浮窗由 PowerShell 加载 Windows Presentation Foundation。
- Windows PowerShell（`powershell.exe`）。
- Windows Script Host，用于运行 `.vbs` 后台启动器。
- Windows COM 组件，用于创建桌面快捷方式。

如果 PowerShell、VBS/Windows Script Host 或相关 COM 能力被企业安全策略、应用控制策略或安全软件禁用，启动器或快捷方式安装脚本可能无法使用。此时需要由系统管理员放行相应功能。

状态识别还依赖当前用户目录中的 Codex 本地数据：

- `%USERPROFILE%\.codex\sessions`：会话事件记录。
- `%USERPROFILE%\.codex\logs_2.sqlite`：用于补充确认任务是否已经产生最终回复。
- `%USERPROFILE%\.codex\auth.json`：用于读取当前 Codex 登录账户的访问令牌和账户 ID，以查询可用重置次数。

若尚未登录 Codex、本地日志目录不存在、日志格式在后续 Codex 版本中发生变化，部分状态或额度可能显示为 `--`。精确的完成状态检测还需要 Codex 内置 Python 运行时，或系统 `PATH` 中可用的 `python.exe`；Python 不可用时悬浮窗仍可运行，但完成状态判断可能不够及时。

## 数据来源与隐私

对话状态来自本机 Codex 会话及日志数据。工作期间的 5 小时额度和一周额度会优先跟随本地会话事件更新；空闲期间，工具会读取 `auth.json` 中当前账户的凭据，并向以下 ChatGPT 官方接口发起经过身份验证的请求：

```text
https://chatgpt.com/backend-api/wham/usage
https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
```

前一个接口用于获取 5 小时和一周额度，后一个接口用于获取可用重置次数和过期日期。工具不会把本地会话日志或对话内容上传到这些接口，也不会向其他服务发送数据。

## 主要文件

- `CodexStatusWidget.ps1`：悬浮窗界面、状态聚合、额度显示和交互逻辑。
- `CodexLogStateProbe.py`：以只读方式查询 `logs_2.sqlite`，补充判断最终回复是否完成。
- `Start-CodexStatusWidget.vbs`：隐藏 PowerShell 控制台并启动悬浮窗。
- `Install-DesktopShortcut.ps1`：创建桌面快捷方式。
- `Test-CodexStatusWidget.ps1`：状态机和额度行为测试。
- `Test-MultiConversationLamp.ps1`：多对话状态灯测试。

## 常见问题

### 额度或重置次数显示为 `--`

确认 Codex Desktop 已登录，并且网络可以访问 `chatgpt.com`。空闲状态下刷新 5 小时额度、一周额度、可用重置次数和过期日期都需要有效的 `auth.json` 和网络连接。

### 状态灯没有及时变为乳白色

确认 Codex 内置 Python 运行时仍然存在，或 `python.exe` 已加入系统 `PATH`。Python 辅助程序不可用时，工具只能依赖会话事件判断完成状态。

### 双击启动后没有出现窗口

检查 Windows Script Host 和 Windows PowerShell 是否被系统策略禁用。悬浮窗默认位于主屏幕工作区右下角；如果窗口被遮挡或移动到其他屏幕，再次双击桌面快捷方式即可将已有窗口移回主屏右下角并置顶。数据查询期间可能需要等待当前刷新结束。

启动器会自动补齐子进程的 `SystemRoot` 和 `windir`，并使用系统目录下的 PowerShell 完整路径。当启动宿主遗漏这些环境变量时，旧启动器可能在执行脚本前出现 `8009001d`，或窗口组件初始化失败。此修复仅影响启动器及其子进程，不修改系统环境变量。启动失败会显示错误提示；脚本初始化异常会写入下述日志。

窗口会先显示再刷新数据；日志辅助查询超过 750 毫秒时会终止辅助进程，当前刷新改用会话事件结果，避免数据库查询卡住窗口。

### 排查运行错误

无法处理的刷新异常会写入项目目录下的 `CodexStatusWidget-errors.log`。该文件仅在出现相应错误时创建。
