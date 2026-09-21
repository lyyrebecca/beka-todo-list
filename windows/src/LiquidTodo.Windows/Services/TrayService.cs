using System.Drawing;
using Forms = System.Windows.Forms;

namespace LiquidTodo.Windows.Services;

internal sealed class TrayService : IDisposable
{
    private readonly Forms.NotifyIcon _icon;
    public TrayService(string iconFile, Action showHide, Action add, Action desktop, Func<bool> desktopEnabled,
        Action startup, Func<bool> startupEnabled, Action import, Action export, Action clearArchived, Action exit)
    {
        _icon = new Forms.NotifyIcon { Text = "贝卡の Todo list", Visible = true, Icon = new Icon(iconFile) };
        var menu = new Forms.ContextMenuStrip();
        menu.Opening += (_, _) =>
        {
            menu.Items.Clear();
            menu.Items.Add("显示 / 隐藏", null, (_, _) => showHide());
            menu.Items.Add("添加待办", null, (_, _) => add());
            var desktopItem = menu.Items.Add("沉入桌面（纯展示，不可点击）", null, (_, _) => desktop()); desktopItem.Checked = desktopEnabled();
            var startupItem = menu.Items.Add("开机自动启动", null, (_, _) => startup()); startupItem.Checked = startupEnabled();
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("导入备份…", null, (_, _) => import());
            menu.Items.Add("导出备份…", null, (_, _) => export());
            menu.Items.Add("清空已完成", null, (_, _) => clearArchived());
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("退出 贝卡の Todo list", null, (_, _) => exit());
        };
        _icon.ContextMenuStrip = menu;
        _icon.DoubleClick += (_, _) => showHide();
    }
    public void Balloon(string title, string text) => _icon.ShowBalloonTip(5000, title, text, Forms.ToolTipIcon.Info);
    public void Dispose() { _icon.Visible = false; _icon.Dispose(); }
}
