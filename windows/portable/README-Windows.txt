贝卡の Todo list - Windows Portable
====================================

1. 请先把整个 ZIP 解压到普通文件夹，再双击 LiquidTodo.exe。
   不要在 ZIP 预览窗口里直接运行，也不要只移动 LiquidTodo.exe 或 Assets 文件夹。
2. 本版本为 Windows 10 22H2 / Windows 11 x64 自包含版本，不需要安装 .NET。
3. 首次运行后，程序会在同级自动创建 Data 文件夹，用于保存待办和日志。
   想保留数据时，请不要删除或移动该文件夹。
4. 如果 SmartScreen 显示“未知发布者”，请确认文件来自项目 GitHub Releases，
   再选择“更多信息 -> 仍要运行”。
5. 若应用未能启动，Data\Logs 中会有 startup-*.log。
   可用命令 LiquidTodo.exe --safe-mode --diagnostics 以基础模式启动。

数据完全离线保存在本机，不会上传。
