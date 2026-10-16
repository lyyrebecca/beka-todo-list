# 贝卡の Todo list 🌟

<p align="center"><img src="public-assets/app-icon.png" width="132" alt="贝卡の Todo list 图标"></p>

<p align="center"><strong>离线、本地优先的 Mac / Windows 桌面待办。</strong><br>收起后是可拖动、自动贴边的紫色「干」悬浮球。</p>

<p align="center"><img src="public-assets/screenshots/todo-panel.png" width="49%" alt="macOS 版 Todo list 主界面"> <img src="public-assets/screenshots/windows-todo-panel.png" width="49%" alt="Windows 版 Todo list 主界面"></p>
<p align="center"><sub>左：macOS · 右：Windows x64；Windows 图由 GitHub Windows runner 实际渲染，使用演示数据</sub></p>

## 选哪个下载？

| 你的电脑 | 下载文件 | 适合谁 | 打开方式 |
|---|---|---|---|
| **Mac（Intel 或 Apple 芯片）** | [`LiquidTodo-macOS-universal-v2.0.1.zip`](https://github.com/lyyrebecca/beka-todo-list/releases/download/v2.0.1/LiquidTodo-macOS-universal-v2.0.1.zip) | 所有 Mac 用户 | 解压后把 `LiquidTodo.app` 拖进“应用程序”，双击打开。 |
| **Windows 10 22H2 / Windows 11 x64** | [`LiquidTodo-Windows-x64-Setup-v2.0.1.exe`](https://github.com/lyyrebecca/beka-todo-list/releases/download/v2.0.1/LiquidTodo-Windows-x64-Setup-v2.0.1.exe) | 推荐，大多数 Windows 用户 | 双击安装器，按提示安装；可选桌面快捷方式与开机启动。 |
| **Windows 10 22H2 / Windows 11 x64** | [`LiquidTodo-Windows-x64-Portable-v2.0.1.zip`](https://github.com/lyyrebecca/beka-todo-list/releases/download/v2.0.1/LiquidTodo-Windows-x64-Portable-v2.0.1.zip) | 不想安装、想放 U 盘 | 解压整个文件夹，双击 `LiquidTodo.exe`；首次启动会在同级创建 `Data/`，之后不要删除它。 |

> **Windows 版无需安装 .NET。** 若 SmartScreen 显示“未知发布者”，点击 **更多信息 → 仍要运行**；这是因为目前尚未使用 Authenticode 证书。只从 [Releases](../../releases/latest) 下载，并用 `SHA256SUMS.txt` 核对文件。

## 下载后，到底双击哪个文件？（新手必看）

**Mac：打开「应用程序」里的 `LiquidTodo.app`。Windows 安装版：打开桌面或开始菜单里的「贝卡の Todo list」。Windows 便携版：打开完整解压文件夹里的 `LiquidTodo.exe`。**

### 第一步：从正确位置下载

1. 打开 [正式版下载页面（Releases）](https://github.com/lyyrebecca/beka-todo-list/releases/latest)。
2. 找到页面底部的 **Assets（资源）**，若列表折叠，先点开；按上表选择 **一个**与你的系统对应的文件即可。
3. **不要下载 `Source code (zip)` / `Source code (tar.gz)`**，也不要点项目绿色 **Code → Download ZIP**：这些是开发源码，不是可直接使用的软件。普通用户也不需要到 Packages 下载，不需要 Docker、编程工具或 .NET。

### Mac：解压 → 移到“应用程序” → 打开 App

适用 **macOS 14 或更新系统**，Intel / Apple 芯片共用同一份 Universal 包。

1. 下载 `LiquidTodo-macOS-universal-v2.0.1.zip`。
2. 在 **访达 → 下载** 中双击 ZIP 解压，找到紫色图标的 **`LiquidTodo.app`**。如果浏览器已经自动解压，直接找这个 App，不用再次解压。
3. 把 **整个 `LiquidTodo.app`** 拖到访达左侧的 **应用程序（Applications）**。
4. 打开 **访达 → 应用程序 → `LiquidTodo.app`**，双击启动。系统隐藏 `.app` 扩展名时，可能只显示 `LiquidTodo`；中文显示名也可能是「贝卡の Todo list」。认准紫色应用图标即可。
5. 首次启动设置自己的名称，随后点主面板右上方 **＋** 添加待办。

```text
下载/LiquidTodo-macOS-universal-v2.0.1.zip
    ↓ 双击解压，把整个 App 拖到“应用程序”
应用程序/（Applications）
└── LiquidTodo.app    ← 每次使用，双击这个紫色 App
```

**不需要右键“显示包内容”，也不要进入 `Contents/MacOS/` 找内部程序。** 这是桌面/菜单栏小组件，没有常规 Dock 窗口也不代表没启动：先看桌面上的面板或紫色「干」球；被隐藏时，点屏幕顶部菜单栏的待办图标，再选“显示桌面组件 / 展开桌面组件”。

若 macOS 首次提示开发者无法验证，请先核对下载来源与 SHA-256，再到 **系统设置 → 隐私与安全性** 查看对应的打开选项；**不要关闭系统安全保护，也不要照着陌生教程执行终端解禁命令**。提示“文件已损坏”时先重新下载完整文件并校验。

### Windows 安装版（推荐）：双击 Setup，装好后打开快捷方式

适用 **Windows 10 22H2 / Windows 11 x64**。

1. 下载 **`LiquidTodo-Windows-x64-Setup-v2.0.1.exe`**。这是安装器，**不需要解压**。
2. 双击安装器，跟随提示安装；建议勾选 **创建桌面快捷方式**。是否开机启动可自行选择。
3. 安装结束后勾选启动应用，或双击桌面的 **「贝卡の Todo list」** 快捷方式。
4. 如果没创建桌面快捷方式：点 **开始菜单**，搜索 **贝卡**，打开 **「贝卡の Todo list」**。
5. 如果仍找不到：按 **Win + R**，粘贴下方路径，按回车。下方是默认安装位置；若安装时自行更改目录，请打开所选目录中的 `LiquidTodo.exe`。

```text
%LOCALAPPDATA%\Programs\LiquidTodo\LiquidTodo.exe
```

**以后打开桌面/开始菜单快捷方式即可，不要每次重新运行 `Setup` 安装器。** 自定义待办名称不会改变安装器、程序文件或默认快捷方式的名称。

### Windows 便携版：先“全部解压”，再打开 `LiquidTodo.exe`

1. 下载 **`LiquidTodo-Windows-x64-Portable-v2.0.1.zip`**。
2. 在文件资源管理器中右键 ZIP → **全部解压…**。例如解压到 `D:\Apps\LiquidTodo\`（这是示例，可以换成你自己的可写文件夹）。
3. 打开 **解压后的文件夹**，找到与许多 `.dll` 文件放在同一层的 **`LiquidTodo.exe`**，双击它。
4. 如果还套着一层文件夹，就再打开一层，直到看到 `LiquidTodo.exe`。Windows 隐藏扩展名时，它显示为 **`LiquidTodo`**，文件“类型”为 **应用程序**，不是配置文件或文件夹。
5. 首次启动会在程序旁生成 **`Data`** 文件夹，保存你的待办和设置；以后继续从这里的 `LiquidTodo.exe` 打开。

```text
D:\Apps\LiquidTodo\                  ← 示例：完整解压得到的文件夹
├── LiquidTodo.exe                   ← 双击这个！类型为“应用程序”
├── LiquidTodo.dll                   ← 不点、不单独移动
├── LiquidTodo.runtimeconfig.json    ← 配置文件，不是启动入口
├── Assets\                          ← 资源，保留
├── portable.flag                    ← 便携模式标识，保留
├── …其他 DLL / 子文件夹             ← 全部保留
└── Data\                            ← 首次运行后生成；你的待办，别删除
```

**不要在 ZIP 压缩包预览里直接运行，也不要只把 EXE 拖到桌面！** 程序依赖同目录资源，必须保留整个解压文件夹。想从桌面快速打开，请右键 `LiquidTodo.exe` → **发送到 → 桌面快捷方式**（Windows 11 可先点“显示更多选项”）；不要移动 EXE 本体。

便携版升级前先退出应用并备份整个 `Data` 文件夹。解压新版、保留原 `Data` 再启动；不要删除旧文件夹后才想起备份。安装版数据在 `%LOCALAPPDATA%\LiquidTodo\`，便携版在 EXE 同级 `Data\`，两者不是同一个目录。

### 双击了，但找不到界面？

- **Windows**：先看屏幕边缘的紫色「干」球，点一下展开；再看任务栏右下角，点 **⌃ 显示隐藏图标**，右键待办图标 → **显示 / 隐藏**。开机启动也可能以圆球或上次状态出现。
- **Mac**：看屏幕边缘的「干」球，或屏幕顶部菜单栏的待办图标，选择显示/展开组件。不要因为 Dock 没出现常规窗口就重复启动。
- **v2.0.1 已知问题**：Windows 悬浮球拖动后可能移出工作区，修复版 v2.0.2 正在客户端验收，尚未正式发布。旧版没有“找回窗口”菜单；不要把该候选版操作当作旧版已有功能。
- 若任务管理器中进程出现后立即消失，不算启动成功；先确认完整解压，再参考本页末尾 **Windows Portable 无法启动？** 收集诊断日志。

## 三步开始使用

1. 下载上表中与你的系统对应的文件并打开应用。
2. 第一次启动会询问名称：可用默认“贝卡”，也可填写“小王”，标题即显示为“小王の Todo list”。之后随时点标题栏 **⚙** 修改。
3. 点 **＋** 新建待办；可设普通 / 重要 / 紧急、截止日期 / 某一天 / 期间，以及到时、前一天 21:00、期间每日提醒。

### 日常操作

- **编辑**：点击待办文字；标题、级别、日期、时间和提醒均可修改。
- **排序**：拖动每条最右侧的 `⋮⋮` 手柄；重要 / 紧急项目创建后自动置顶。
- **收起**：点 `−` 变为紫色「干」圆球，拖到屏幕边缘会自动吸附；点击圆球恢复。
- **完成**：勾选后有 4 秒撤销窗口；完成历史可恢复或清空。
- **备份**：托盘菜单中选择“导出备份 / 导入备份”。导入默认安全合并，按 UUID 去重，导入前自动备份本机数据。

## 功能

| 能力 | macOS | Windows x64 |
|---|---:|---:|
| 创建、完整编辑、拖动排序、三级重要度 | ✅ | ✅ |
| 截止日期、某一天、期间与提醒 | ✅ | ✅ |
| 完成、4 秒撤销、历史恢复 | ✅ | ✅ |
| 中文输入法、悬浮球、托盘、开机启动 | ✅ | ✅ |
| 自定义 `xxの Todo list` 名称 | ✅ | ✅ |
| 跨平台 JSON 导入 / 导出 | ✅ | ✅ |

## 数据与隐私

完全离线：无账号、遥测、广告、云同步或自动更新。

- **Mac**：`~/Library/Application Support/LiquidTodo/`
- **Windows 安装版**：`%LOCALAPPDATA%\LiquidTodo\`
- **Windows 便携版**：应用同级 `Data/`

备份格式为 [LiquidTodo Backup v1](shared/backup-schema/liquidtodo-backup-v1.schema.json)，可在 Mac 和 Windows 间手动迁移。

常规用户请从 [GitHub Releases](../../releases/latest) 选择上表对应的安装包。GitHub Packages 中的 `ghcr.io/lyyrebecca/beka-todo-list` 是下载文件镜像，包含 macOS ZIP、Windows Setup EXE、Windows Portable ZIP 和 SHA-256 清单，供偏好容器仓库的用户下载；不需要 Docker 的用户无需使用它。

## 开发与验证

```bash
# macOS
./test.sh && ./build.sh

# Windows（Windows x64 上）
dotnet test windows/LiquidTodo.Windows.sln
dotnet publish windows/src/LiquidTodo.Windows -c Release -r win-x64 --self-contained true
```

Windows CI 会跑单元测试并构建自包含发布产物；最新通过记录见 [Actions](../../actions)。

### Windows Portable 无法启动？

请确认先**完整解压 ZIP**，而不是在压缩包预览中直接双击，也不要只拷走 `LiquidTodo.exe`。Portable 版本必须与同目录的 DLL、`LiquidTodo.runtimeconfig.json`、资源文件一起运行。

若双击后进程仍立即退出，请运行：

```powershell
.\LiquidTodo.exe --safe-mode --diagnostics
```

它会跳过托盘、通知和桌面展示模式，只打开基础待办面板；启动错误会写入同级 `Data\Logs\startup-*.log`。请附上该日志与 Windows 版本信息提交 Issue。每个 Release 都包含 `manifest.json`（包内逐文件 SHA-256）及总文件 `SHA256SUMS.txt`，可用于确认下载完整性。

[MIT](LICENSE)
