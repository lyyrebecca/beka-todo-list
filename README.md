# 贝卡の Todo list 🌟

<p align="center"><img src="public-assets/app-icon.png" width="132" alt="LiquidTodo 图标"></p>

离线、本地优先的桌面待办：macOS 原生 SwiftUI/AppKit 与 Windows 原生 .NET 8 WPF 客户端。收起后是可拖动、自动贴边的紫色「干」悬浮球。

## v2.0.0：macOS + Windows

| 能力 | macOS | Windows 10 22H2 / Windows 11 x64 |
|---|---:|---:|
| 新建、完整编辑、拖动排序、三档重要级别 | ✅ | ✅ |
| 截止日期、某一天、期间、提醒 | ✅ | ✅ |
| 完成、4 秒撤销、历史恢复 | ✅ | ✅ |
| 中文输入法、悬浮球、托盘、开机启动 | ✅ | ✅ |
| 首次自定义标题（`xxの Todo list`） | ✅ | ✅ |
| JSON 导入导出（LiquidTodo Backup v1） | ✅ | ✅ |

首次打开时可将默认「贝卡」换成任意名字，显示为 `xxの Todo list`；Mac 点标题栏齿轮、Windows 点标题栏 ⚙ 可随时修改。

## 下载

Release `v2.0.0` 将提供：

- `LiquidTodo-macOS-universal-v2.0.0.zip`
- `LiquidTodo-Windows-x64-Setup-v2.0.0.exe`（当前用户安装，无需管理员权限）
- `LiquidTodo-Windows-x64-Portable-v2.0.0.zip`（解压即用，数据保存在旁边的 `Data/`）
- `SHA256SUMS.txt`

Windows 首版没有 Authenticode 证书，SmartScreen 显示「未知发布者」时选择 **更多信息 → 仍要运行**。请只从 [GitHub Releases](../../releases/latest) 下载，并用 `certutil -hashfile 文件名 SHA256` 与 `SHA256SUMS.txt` 校验。

## 隐私与备份

完全离线：无账号、遥测、广告、云同步或自动更新。Windows 数据位于 `%LOCALAPPDATA%\LiquidTodo\`（便携版为程序旁 `Data/`）；Mac 数据位于 `~/Library/Application Support/LiquidTodo/`。备份格式规范见 [`shared/backup-schema/liquidtodo-backup-v1.schema.json`](shared/backup-schema/liquidtodo-backup-v1.schema.json)；导入前自动备份，默认合并且 UUID 去重。

## 构建与验证

```bash
# macOS
./test.sh && ./build.sh
# Windows（Windows x64 上）
dotnet test windows/LiquidTodo.Windows.sln
dotnet publish windows/src/LiquidTodo.Windows -c Release -r win-x64 --self-contained true
```

Windows CI 会构建自包含程序并跑核心单元测试。发布前另在 Azure Windows 10/11 云桌面执行安装、通知、微软拼音/微信输入法、开机启动、多显示器 DPI 和真实截图验收。

[MIT](LICENSE)
