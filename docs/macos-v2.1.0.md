# macOS v2.1.0 验收范围

本次仅发布 Mac 更新。用户已要求停止 Windows 虚拟机测试；Windows 代码和正式包保持原状，不把开发分支中的功能混入稳定分发。

## 可重复检查

```sh
./test.sh
./Tests/run-status-item-tests.sh
./Tests/run-ime-focus-tests.sh /tmp/LiquidTodo-IME-check
./Tests/run-layout-tests.sh /tmp/LiquidTodo-layout-check
./build.sh
codesign --verify --deep --strict LiquidTodo.app
lipo -archs LiquidTodo.app/Contents/MacOS/LiquidTodo
```

- 模型/层级/备份/拖动：57 项；菜单：15 项；原生输入客户端：11 项。
- 原生布局和输入事件坐标：7 项；一行窗口切到历史、长历史、26条展开、新建表单均必须扩展到非零、有上限的 viewport。
- 截图时复现历史列表被压扁：旧版高度始终123pt；修复后四条历史310pt、长历史434pt、展开长清单485pt、新建表单434pt。回归先失败后通过。
- 自适应滚动区测量实际内容高度，避免 `maxHeight` 从旧矮窗口继承压缩提议；不是以固定行高裁掉长标题。
- 鼠标处理使用事件自身的窗口/屏幕位置，不依赖全局硬件光标位置，兼容转发输入。

## 真实交互与截图

项目首页的功能图直接由同版生产界面运行后截图，不是图片生成器模拟。演示入口只隔离数据/通知、切换 AppKit 外观；不改 SwiftUI 布局。示例名称和清单均为合成数据。

本机微信输入法用实际拼音键提交中文；子项创建、折叠、父树完成/撤销/归档/恢复、改挂、可变行高与整树拖动有实际鼠标/菜单证据。原生组件的候选锚点测试不能替代所有第三方输入法候选弹窗位置的可见性验收。

## 未覆盖及兼容

- Intel 二进制完成交叉编译/签名检查，未在 Intel 硬件上运行。
- 屏幕边缘自动滚动未提供；先滚到目标附近，再拖动同级手柄。
- 含层级备份为 v2；旧 Mac / Windows v2.0.1 不支持。平面清单仍为 v1。
- Windows 新版客户端、混合DPI和Windows10验收未完成，故不发布新版 Windows。
