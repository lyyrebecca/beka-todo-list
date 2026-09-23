using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using LiquidTodo.Core;
using LiquidTodo.Windows.Services;
using Microsoft.Win32;

namespace LiquidTodo.Windows;

public partial class MainWindow : Window
{
    private const double PanelWidth = 362, OrbSize = 48;
    private string OwnerName => string.IsNullOrWhiteSpace(_settings.OwnerName) ? "贝卡" : _settings.OwnerName!;
    private readonly LiquidTodoPaths _paths;
    private readonly TodoStore _store;
    private readonly SettingsService _settingsService;
    private AppSettings _settings;
    private readonly StartupService _startup = new();
    private readonly TrayService? _tray;
    private readonly ToastNotificationService? _toasts;
    private readonly bool _safeMode;
    private readonly Dictionary<Guid, System.Windows.Threading.DispatcherTimer> _undoTimers = [];
    private System.Windows.Point _orbStartMouse, _orbStartWindow;
    private bool _orbDragging;
    private bool _ready;
    private bool _showAllItems;

    public MainWindow(LiquidTodoPaths paths, TodoStore store, string[] arguments, bool safeMode = false)
    {
        InitializeComponent();
        _paths = paths; _store = store; _safeMode = safeMode; _settingsService = new SettingsService(paths.SettingsFile); _settings = _settingsService.Load();
        InitializeGlassBackground();
        ApplyTheme();
        SystemEvents.UserPreferenceChanged += SystemPreferenceChanged;
        if (!safeMode)
        {
            // Publish preserves the Assets directory.  Looking beside the EXE was
            // the direct cause of the released Portable build exiting on startup.
            _tray = new TrayService(Path.Combine(AppContext.BaseDirectory, "Assets", "LiquidTodo.ico"), ToggleVisible, StartAdd, ToggleDesktopMode, () => _settings.DesktopMode, ToggleStartup, () => _startup.IsEnabled, ImportBackup, ExportBackup, ClearArchived, () => System.Windows.Application.Current.Shutdown());
            _toasts = new ToastNotificationService(_tray.Balloon);
        }
        else
        {
            ShowInTaskbar = true;
            SafeExitButton.Visibility = Visibility.Visible;
            MinimizeButton.Visibility = Visibility.Collapsed;
            DesktopButton.Visibility = Visibility.Collapsed;
        }
        _store.Changed += (_, _) => Dispatcher.Invoke(Render);
        Loaded += (_, _) =>
        {
            ApplyInitialPosition();
            if (!safeMode) EnsureOwnerName();
            if (!safeMode && _settings.IsMinimized) SetMinimized(true, false); else Render();
            if (!safeMode) ApplyDesktopMode();
            if (_store.RecoveryMessage is { } message) _tray?.Balloon("数据已恢复", message);
            if (TryReadImport(arguments, out var import)) ImportBackup(import);
            _ready = true;
        };
        Closed += (_, _) => { SystemEvents.UserPreferenceChanged -= SystemPreferenceChanged; _toasts?.Dispose(); _tray?.Dispose(); foreach (var timer in _undoTimers.Values) timer.Stop(); };
    }

    private void InitializeGlassBackground()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "LiquidGlassPanel.png");
        if (!File.Exists(path)) return;
        try
        {
            var image = new BitmapImage();
            image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.UriSource = new Uri(path); image.EndInit(); image.Freeze();
            GlassImageLayer.Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill, Opacity = .9 };
        }
        catch { GlassImageLayer.Background = new SolidColorBrush(Color.FromRgb(238, 233, 255)); }
    }

    private void ApplyTheme()
    {
        var darkMode = WindowsThemeService.IsDarkMode();
        WindowsThemeService.ApplyResources(darkMode);
        if (GlassImageLayer.Background is ImageBrush imageBrush) imageBrush.Opacity = darkMode ? .48 : .92;
    }

    private void SystemPreferenceChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category is not (UserPreferenceCategory.General or UserPreferenceCategory.Color)) return;
        Dispatcher.BeginInvoke(new Action(ApplyTheme));
    }

    public void ActivateFromSecondLaunch(string command)
    {
        if (_settings.IsMinimized) SetMinimized(false, true);
        Show(); WindowState = WindowState.Normal; Topmost = !_settings.DesktopMode; Activate(); Focus();
        if (command == "import") _tray?.Balloon("贝卡の Todo list", "已有实例已唤醒；请从托盘菜单选择导入备份。");
    }

    /// <summary>Used by the Windows CI runner to retain visual evidence of a real WPF render.</summary>
    public void CaptureScreenshotAndExit(string outputPath)
    {
        Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
        {
            try
            {
                UpdateLayout();
                var width = Math.Max(1, (int)Math.Ceiling(ActualWidth));
                var height = Math.Max(1, (int)Math.Ceiling(ActualHeight));
                var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(this);
                var directory = Path.GetDirectoryName(outputPath);
                if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var stream = File.Create(outputPath);
                encoder.Save(stream);
            }
            finally { System.Windows.Application.Current.Shutdown(); }
        }));
    }

    private static bool TryReadImport(IEnumerable<string> args, out string file)
    {
        var values = args.ToArray(); var pos = Array.FindIndex(values, x => x.Equals("--import", StringComparison.OrdinalIgnoreCase));
        file = pos >= 0 && pos + 1 < values.Length ? values[pos + 1] : ""; return File.Exists(file);
    }

    private void ApplyInitialPosition()
    {
        if (_settings.Left is { } left && double.IsFinite(left) && _settings.Top is { } top && double.IsFinite(top)) { Left = left; Top = top; }
        else { Left = Math.Max(16, SystemParameters.WorkArea.Right - PanelWidth - 60); Top = Math.Max(16, SystemParameters.WorkArea.Top + 70); }
    }

    private void Render()
    {
        if (_settings.IsMinimized && !_safeMode) return;
        ItemsHost.Children.Clear();
        var showArchive = ArchiveButton.Tag as string == "archive";
        var source = showArchive ? _store.Archived : _store.Items;
        Title = $"{OwnerName}の Todo list";
        NameTitle.Text = $"{OwnerName}の Todo list";
        SubTitle.Text = showArchive ? $"已完成 {source.Count} 项" : _store.Items.Count == 0 ? "今天，把一件事做好" : $"还有 {_store.Items.Count} 项待办";
        ArchiveButton.Content = showArchive ? "‹" : "◷";
        if (source.Count == 0)
            ItemsHost.Children.Add(new TextBlock { Text = showArchive ? "还没有已完成的待办" : "暂无待办，点下方 + 添加", Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(4, 14, 4, 14), FontSize = 12, TextAlignment = TextAlignment.Center });
        var limit = showArchive || _showAllItems ? source.Count : Math.Min(10, source.Count);
        foreach (var item in source.Take(limit)) ItemsHost.Children.Add(showArchive ? CreateArchiveRow(item) : CreateTodoRow(item));
        if (!showArchive && source.Count > 10)
        {
            var toggle = new Button { Content = _showAllItems ? "⌃  收起" : $"⌄  还有 {source.Count - 10} 条", Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = (Brush)FindResource("Purple"), Padding = new Thickness(8, 6, 8, 6), HorizontalContentAlignment = System.Windows.HorizontalAlignment.Left, Cursor = Cursors.Hand };
            toggle.Click += (_, _) => { _showAllItems = !_showAllItems; Render(); };
            ItemsHost.Children.Add(toggle);
        }
        if (showArchive && source.Count > 0)
        {
            var clear = new Button { Content = "清空全部已完成", Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = (Brush)FindResource("Muted"), Padding = new Thickness(6), Cursor = Cursors.Hand };
            clear.Click += (_, _) => ClearArchived(); ItemsHost.Children.Add(clear);
        }
        AddButton.Visibility = showArchive ? Visibility.Collapsed : Visibility.Visible;
        var visibleCount = showArchive ? Math.Min(7, source.Count) : Math.Min(_showAllItems ? 8 : 10, source.Count);
        AnimateTo(PanelWidth, Math.Max(190, Math.Min(640, 150 + visibleCount * 48 + (showArchive ? 48 : 42))), false);
        _toasts?.Rebuild(_store.UpcomingReminders(DateTimeOffset.Now));
    }

    private Border CreateTodoRow(TodoItem item)
    {
        var row = new Border { Background = (Brush)FindResource("RowFill"), CornerRadius = new CornerRadius(12), Padding = new Thickness(8, 6, 6, 6), Margin = new Thickness(0, 3, 0, 3), Tag = item.Id };
        var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(25) }); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(15) }); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) }); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(25) }); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        var done = new CheckBox { VerticalAlignment = VerticalAlignment.Center, ToolTip = item.Completed ? "撤销完成" : "标记为完成", IsChecked = item.Completed, IsThreeState = false };
        done.Checked += (_, _) => { if (!item.Completed) CompleteWithUndo(item.Id); };
        done.Unchecked += (_, _) => { if (item.Completed) { if (_undoTimers.Remove(item.Id, out var timer)) timer.Stop(); _store.UndoCompletion(item.Id); } };
        Grid.SetColumn(done, 0); grid.Children.Add(done);
        if (item.Priority != TodoPriority.Normal)
        {
            var badge = new TextBlock { Text = item.Priority == TodoPriority.Important ? "★" : "‼", Foreground = (Brush)FindResource(item.Priority == TodoPriority.Important ? "Important" : "Urgent"), FontSize = 11, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center, ToolTip = item.Priority == TodoPriority.Important ? "重要" : "紧急" };
            Grid.SetColumn(badge, 1); grid.Children.Add(badge);
        }
        var text = new TextBlock { Text = item.Text, Foreground = item.Completed ? (Brush)FindResource("Muted") : (Brush)FindResource("Ink"), VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, Cursor = Cursors.Hand, TextDecorations = item.Completed ? TextDecorations.Strikethrough : null };
        text.MouseLeftButtonUp += (_, _) => Edit(item); Grid.SetColumn(text, 2); grid.Children.Add(text);
        var label = new TextBlock { Text = LabelFor(item), Foreground = IsOverdue(item) ? (Brush)FindResource("Urgent") : (Brush)FindResource("Purple"), FontSize = 10, VerticalAlignment = VerticalAlignment.Center, TextAlignment = TextAlignment.Right, TextTrimming = TextTrimming.CharacterEllipsis };
        Grid.SetColumn(label, 3); grid.Children.Add(label);
        var edit = new Button { Content = "✎", Width = 22, Height = 24, Padding = new Thickness(0), BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = (Brush)FindResource("Muted"), ToolTip = "编辑待办" };
        System.Windows.Automation.AutomationProperties.SetName(edit, "编辑待办");
        edit.Click += (_, _) => Edit(item); Grid.SetColumn(edit, 4); grid.Children.Add(edit);
        var handle = new Thumb { Width = 18, Height = 28, Cursor = Cursors.SizeAll, ToolTip = "拖动调整顺序", Opacity = .65, Template = CreateHandleTemplate() };
        handle.DragStarted += (_, _) => row.Opacity = .72;
        handle.DragCompleted += (_, _) => { row.Opacity = 1; MoveFromHandle(item.Id, Mouse.GetPosition(ItemsHost)); };
        Grid.SetColumn(handle, 5); grid.Children.Add(handle);
        row.ContextMenu = CreateTodoContextMenu(item);
        row.Child = grid; return row;
    }

    private static ControlTemplate CreateHandleTemplate()
    {
        var factory = new FrameworkElementFactory(typeof(TextBlock)); factory.SetValue(TextBlock.TextProperty, "⋮⋮"); factory.SetValue(TextBlock.ForegroundProperty, Brushes.Gray); factory.SetValue(TextBlock.FontSizeProperty, 12d); factory.SetValue(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center); factory.SetValue(TextBlock.HorizontalAlignmentProperty, System.Windows.HorizontalAlignment.Center); return new ControlTemplate(typeof(Thumb)) { VisualTree = factory };
    }

    private Border CreateArchiveRow(TodoItem item)
    {
        var row = new Border { Background = (Brush)FindResource("RowFill"), CornerRadius = new CornerRadius(11), Padding = new Thickness(10, 7, 8, 7), Margin = new Thickness(0, 3, 0, 3) };
        var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(52) }); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32) });
        grid.Children.Add(new TextBlock { Text = item.Text, Foreground = (Brush)FindResource("Muted"), TextDecorations = TextDecorations.Strikethrough, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });
        var restore = new Button { Content = "恢复", FontSize = 10, Padding = new Thickness(4, 1, 4, 1) }; restore.Click += (_, _) => _store.RestoreArchived(item.Id); Grid.SetColumn(restore, 1); grid.Children.Add(restore);
        var delete = new Button { Content = "×", FontSize = 15, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = (Brush)FindResource("Muted"), ToolTip = "永久删除" }; delete.Click += (_, _) => _store.Delete(item.Id); Grid.SetColumn(delete, 2); grid.Children.Add(delete);
        row.Child = grid; return row;
    }

    private void MoveFromHandle(Guid id, System.Windows.Point point)
    {
        var target = 0;
        foreach (var element in ItemsHost.Children.OfType<Border>().Where(x => x.Tag is Guid other && other != id))
        {
            if (point.Y > element.TranslatePoint(new System.Windows.Point(0, 0), ItemsHost).Y + element.ActualHeight / 2) target++;
        }
        _store.Move(id, target);
    }
    private string LabelFor(TodoItem item)
    {
        var schedule = item.Schedule;
        return schedule?.Mode switch
        {
            TodoTimeMode.Deadline => schedule.Date is { } date ? "截止 " + FormatDate(date, includeTime: true) : "截止",
            TodoTimeMode.Day => schedule.Date is { } date ? FormatDate(date, includeTime: false) : "某一天",
            TodoTimeMode.Period when schedule.StartDate is { } start && schedule.EndDate is { } end =>
                $"{start:MM/dd}–{end:MM/dd}" + (schedule.ReminderMode == TodoReminderMode.DailyDuringPeriod ? $" 每天 {schedule.ReminderTimeMinutes / 60:00}:{schedule.ReminderTimeMinutes % 60:00}" : ""),
            _ => ""
        };
    }

    private bool IsOverdue(TodoItem item)
    {
        if (item.Completed || item.Schedule is null) return false;
        if (item.Schedule.Mode == TodoTimeMode.Period && item.Schedule.EndDate is { } end)
            return end.ToDateTime(TimeOnly.MaxValue) < DateTime.Now;
        return item.Schedule.Date is { } date && date.LocalDateTime < DateTime.Now;
    }

    private static string FormatDate(DateTimeOffset date, bool includeTime)
    {
        var local = date.ToLocalTime();
        var day = local.Date == DateTime.Today ? "今天" : local.Date == DateTime.Today.AddDays(1) ? "明天" : local.ToString("M月d日");
        return includeTime ? $"{day} {local:HH:mm}" : day;
    }

    private ContextMenu CreateTodoContextMenu(TodoItem item)
    {
        var menu = new ContextMenu();
        var edit = new MenuItem { Header = "编辑待办…" }; edit.Click += (_, _) => Edit(item); menu.Items.Add(edit);
        if (item.Schedule is not null)
        {
            var clearTime = new MenuItem { Header = "清除时间安排" };
            clearTime.Click += (_, _) => _store.Update(item.Id, item.Text, item.Priority, null);
            menu.Items.Add(clearTime);
        }
        menu.Items.Add(new Separator());
        var delete = new MenuItem { Header = "删除" }; delete.Click += (_, _) => _store.Delete(item.Id); menu.Items.Add(delete);
        return menu;
    }

    private void CompleteWithUndo(Guid id)
    {
        _store.Complete(id); Render();
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        timer.Tick += (_, _) => { timer.Stop(); _undoTimers.Remove(id); _store.ArchiveCompleted(id); };
        _undoTimers[id] = timer; timer.Start();
        _tray?.Balloon("已完成", "4 秒内点击待办区域的“撤销”可恢复。");
        AddUndoRow(id);
    }
    private void AddUndoRow(Guid id)
    {
        var undo = new Button { Content = "已完成 · 撤销", Background = Brushes.Transparent, BorderBrush = (Brush)FindResource("Purple"), Foreground = (Brush)FindResource("Purple"), Margin = new Thickness(0, 4, 0, 0) };
        undo.Click += (_, _) => { if (_undoTimers.Remove(id, out var t)) t.Stop(); _store.UndoCompletion(id); }; ItemsHost.Children.Insert(0, undo);
    }

    private void AddButton_Click(object sender, RoutedEventArgs e) => StartAdd();
    private void StartAdd() { ActivateFromSecondLaunch("activate"); var editor = new TodoEditorWindow(null) { Owner = this }; if (editor.ShowDialog() == true) { try { _store.Add(editor.TodoText, editor.Priority, editor.Schedule); } catch (ArgumentException ex) { MessageBox.Show(this, ex.Message); } } }
    private void Edit(TodoItem item) { ActivateFromSecondLaunch("activate"); var editor = new TodoEditorWindow(item) { Owner = this }; if (editor.ShowDialog() == true) _store.Update(item.Id, editor.TodoText, editor.Priority, editor.Schedule); }
    private void ArchiveButton_Click(object sender, RoutedEventArgs e) { ArchiveButton.Tag = ArchiveButton.Tag as string == "archive" ? null : "archive"; Render(); }
    private void ClearArchived() { if (_store.Archived.Count > 0 && MessageBox.Show(this, "确定清空全部已完成事项？", "贝卡の Todo list", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes) _store.ClearArchived(); }

    private void CustomizeNameButton_Click(object sender, RoutedEventArgs e) => CustomizeOwnerName();
    private void EnsureOwnerName() { if (_settings.OwnerName is null) CustomizeOwnerName(); }
    private void CustomizeOwnerName() { var dialog = new NameSetupWindow(OwnerName) { Owner = this }; if (dialog.ShowDialog() == true) { var owner = string.IsNullOrWhiteSpace(dialog.OwnerName) ? "贝卡" : dialog.OwnerName[..Math.Min(20, dialog.OwnerName.Length)]; _settings = _settings with { OwnerName = owner }; _settingsService.Save(_settings); Render(); } }

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || IsInsideButton(e.OriginalSource as DependencyObject)) return;
        DragMove();
    }

    private static bool IsInsideButton(DependencyObject? source)
    {
        while (source is not null)
        {
            if (source is ButtonBase) return true;
            source = source is Visual or System.Windows.Media.Media3D.Visual3D
                ? VisualTreeHelper.GetParent(source)
                : LogicalTreeHelper.GetParent(source);
        }
        return false;
    }
    private void SafeExitButton_Click(object sender, RoutedEventArgs e) => System.Windows.Application.Current.Shutdown();
    private void MinimizeButton_Click(object sender, RoutedEventArgs e) => SetMinimized(true, true);
    private void SetMinimized(bool minimized, bool animate)
    {
        _settings = _settings with { IsMinimized = minimized }; _settingsService.Save(_settings);
        Panel.Visibility = minimized ? Visibility.Collapsed : Visibility.Visible; Orb.Visibility = minimized ? Visibility.Visible : Visibility.Collapsed;
        var targetWidth = minimized ? OrbSize : PanelWidth; var targetHeight = minimized ? OrbSize : Math.Max(190, Height);
        AnimateTo(targetWidth, targetHeight, animate); if (minimized) SnapOrb(false); else Render();
    }
    private void AnimateTo(double width, double height, bool animate)
    {
        var oldW = Width; var oldH = Height; Width = width; Height = height;
        if (!animate || !SystemParameters.ClientAreaAnimation) return;
        var duration = new Duration(TimeSpan.FromMilliseconds(220));
        BeginAnimation(WidthProperty, new DoubleAnimation(oldW, width, duration) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        BeginAnimation(HeightProperty, new DoubleAnimation(oldH, height, duration) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
    }

    private void Orb_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { _orbStartMouse = PointToScreen(e.GetPosition(this)); _orbStartWindow = new System.Windows.Point(Left, Top); _orbDragging = false; Orb.CaptureMouse(); }
    private void Orb_MouseMove(object sender, System.Windows.Input.MouseEventArgs e) { if (!Orb.IsMouseCaptured || e.LeftButton != MouseButtonState.Pressed) return; var now = PointToScreen(e.GetPosition(this)); var dx = now.X - _orbStartMouse.X; var dy = now.Y - _orbStartMouse.Y; if (Math.Abs(dx) + Math.Abs(dy) > 2) _orbDragging = true; Left = _orbStartWindow.X + dx; Top = _orbStartWindow.Y + dy; }
    private void Orb_MouseLeftButtonUp(object sender, MouseButtonEventArgs e) { Orb.ReleaseMouseCapture(); if (_orbDragging) SnapOrb(true); else SetMinimized(false, true); }
    private void SnapOrb(bool animate)
    {
        var hwnd = new WindowInteropHelper(this).Handle; var screen = Forms.Screen.FromHandle(hwnd); var area = screen.WorkingArea;
        var target = WindowSnapService.SnapToNearestEdge(new RectD(Left, Top, Width, Height), new RectD(area.Left, area.Top, area.Width, area.Height));
        var oldLeft = Left; Left = target.X; Top = target.Y;
        if (animate && SystemParameters.ClientAreaAnimation) BeginAnimation(LeftProperty, new DoubleAnimation(oldLeft, target.X, TimeSpan.FromMilliseconds(180)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        SavePosition();
    }

    private void DesktopButton_Click(object sender, RoutedEventArgs e) => ToggleDesktopMode();
    private void ToggleDesktopMode() { _settings = _settings with { DesktopMode = !_settings.DesktopMode }; _settingsService.Save(_settings); ApplyDesktopMode(); }
    private void ApplyDesktopMode() { if (_safeMode) return; DesktopModeService.Apply(this, _settings.DesktopMode); _tray?.Balloon("贝卡の Todo list", _settings.DesktopMode ? "已沉入桌面：纯展示，鼠标会穿透。" : "已恢复可交互模式。"); }
    private void ToggleStartup() { _startup.SetEnabled(!_startup.IsEnabled); _tray?.Balloon("贝卡の Todo list", _startup.IsEnabled ? "已设为开机自动启动。" : "已关闭开机自动启动。"); }
    private void ToggleVisible() { if (!IsVisible) { Show(); ActivateFromSecondLaunch("activate"); } else Hide(); }
    private void ExportBackup() { var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "LiquidTodo Backup|*.json", FileName = $"LiquidTodo-Backup-{DateTime.Now:yyyyMMdd-HHmmss}.json" }; if (dialog.ShowDialog(this) == true) { _store.Export(dialog.FileName); _tray?.Balloon("导出完成", Path.GetFileName(dialog.FileName)); } }
    private void ImportBackup() { var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "LiquidTodo Backup 或旧版数据|*.json" }; if (dialog.ShowDialog(this) == true) ImportBackup(dialog.FileName); }
    private void ImportBackup(string file)
    {
        try { var replace = MessageBox.Show(this, "默认会安全合并并按 UUID 去重。选择“是”可替换本机全部待办（导入前仍会自动备份）。", "导入备份", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes; var result = _store.Import(file, replace ? ImportMode.Replace : ImportMode.Merge); _tray?.Balloon("导入完成", $"新增 {result.ImportedItems + result.ImportedArchived} 项，跳过 {result.SkippedDuplicates} 项。已自动备份。"); } catch (Exception ex) { MessageBox.Show(this, $"无法导入备份：{ex.Message}", "贝卡の Todo list", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private void SavePosition() { _settings = _settings with { Left = Left, Top = Top }; _settingsService.Save(_settings); }
    protected override void OnLocationChanged(EventArgs e) { base.OnLocationChanged(e); if (_ready) SavePosition(); }
    protected override void OnKeyDown(System.Windows.Input.KeyEventArgs e) { if (e.Key == Key.N && Keyboard.Modifiers == ModifierKeys.Control) { StartAdd(); e.Handled = true; } base.OnKeyDown(e); }
}
