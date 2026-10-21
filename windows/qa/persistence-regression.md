# Windows 保存冲突回归（发布仍受客户端验收门槛约束）

## 实测发现

原候选 `b17214a` 在 Windows 11 客户端完整 UI 流程中，已实际完成 4 秒内鼠标撤销（发出时 2580.966 ms）、排序与历史恢复，随后清空历史时出现 `UnauthorizedAccessException`，位于原子替换 `data.json` 的 `File.Move(overwrite)`。

独立离线内核测试在同一台 Windows 11 Enterprise Evaluation 26H2、build 26300.9457、x64 客户端复现：读取者未授予删除共享时，旧实现的替换失败；只读目标失败后遗留临时文件；有效文件被独占读取时旧实现误报空数据；保存失败后旧内存状态已被修改。

该测试明确运行于 Session 0，**只证明真实 Windows 文件系统语义，不是 GUI、输入法或通知验收**。没有使用个人待办。旧 Core DLL 的四项均失败，修复 Core 的相同四项均通过。

## 修正

- 读者使用 `FileShare.ReadWrite | FileShare.Delete`；保存使用同目录唯一临时文件，写入并 flush 后原子替换。
- 对 Windows 错误 5 / 32 / 33 做有上限的短暂重试，不删除或截断上一份成功文件。永久权限错误仍向界面报告。
- 仅解析/数据格式错误才隔离损坏文件；权限和文件占用不再被误判成损坏或成功加载空清单。
- 写入失败清理本次临时文件；Store 恢复最后成功提交的内存快照，防止下一次操作把此前失败的隐藏修改写入。

## 可重复测试

```powershell
dotnet test windows/tests/LiquidTodo.Windows.Tests/LiquidTodo.Windows.Tests.csproj -c Release --filter FullyQualifiedName~PersistenceRegressionTests
```

先在旧代码运行的 9 项跨平台写入失败回归全部失败；修复后全套跨平台测试 94 项通过。另 3 项使用 Windows 内核共享/只读语义的 xUnit 测试在 Mac 明确标为跳过，不能算成通过；它们需要 Windows runner 执行。独立 Windows 客户端内核对照测试已通过上述四项。

更新后的实际 Setup/Portable 仍须重新执行完整 GUI 回归。Windows 10、真实混合 DPI、多显示器、微软拼音/微信输入法组合输入和通知中心等未覆盖项继续保留，不据此发布 Latest 或替换 Packages。
