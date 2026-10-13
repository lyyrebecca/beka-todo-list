using System.Diagnostics;
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
    private NativeWindow.Point _orbStartMouse;
    private double _grabX, _grabY;
    private bool _orbPressed;
    private readonly DispatcherTimer _positionSaveTimer = new() { Interval = TimeSpan.FromMilliseconds(300) };
    private readonly DispatcherTimer _snapTimer = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private RectD? _motionTarget, _motionStart;
    private readonly Stopwatch _motionClock = new();
    private bool _settingsErrorReported;
    private bool _orbDragging;
    private bool _ready;
    private bool _showAllItems;
    private HwndSource? _themeSource;

    public MainWindow(LiquidTodoPaths paths, TodoStore store, string[] arguments, bool safeMode = false)
    {
        InitializeComponent();
        _paths = paths; _store = store; _safeMode = safeMode; _settingsService = new SettingsService(paths.SettingsFile); _settings = _settingsService.Load();
        ApplyTheme();
        SourceInitialized += (_, _) => { _themeSource = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle); _themeSource?.AddHook(ThemeMessage); };
        SystemEvents.UserPreferenceChanged += SystemPreferenceChanged;
        SystemEvents.DisplaySettingsChanged += DisplaySettingsChanged;
        SystemEvents.PowerModeChanged += PowerModeChanged;
        _positionSaveTimer.Tick += (_, _) => { _positionSaveTimer.Stop(); SavePosition(); };
        _snapTimer.Tick += (_, _) => TickSnap();
        if (!safeMode)
        {
            // Publish preserves the Assets directory.  Looking beside the EXE was
            // the direct cause of the released Portable build exiting on startup.
            _tray = new TrayService(Path.Combine(AppContext.BaseDirectory, "Assets", "LiquidTodo.ico"), ToggleVisible, StartAdd, ToggleDesktopMode, () => _settings.DesktopMode, ToggleStartup, () => _startup.IsEnabled, ImportBackup, ExportBackup, ClearArchived, () => System.Windows.Application.Current.Shutdown(), RecoverWindow);
            _toasts = new ToastNotificationService(_tray.Balloon, _store.UpcomingReminders, () => $"{OwnerName}の Todo list");
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
        Closing += (_, _) => { _positionSaveTimer.Stop(); StopSnap(); if (_ready) SavePosition(); _ready = false; };
        Closed += (_, _) => { _themeSource?.RemoveHook(ThemeMessage); _positionSaveTimer.Stop(); _snapTimer.Stop(); SystemEvents.DisplaySettingsChanged -= DisplaySettingsChanged; SystemEvents.PowerModeChanged -= PowerModeChanged; SystemEvents.UserPreferenceChanged -= SystemPreferenceChanged; _toasts?.Dispose(); _tray?.Dispose(); foreach (var timer in _undoTimers.Values) timer.Stop(); };
    }

    private void ApplyTheme()
    {
        var darkMode = WindowsThemeService.IsDarkMode();
        WindowsThemeService.ApplyResources(darkMode);
        GlassSurface.SetTheme(darkMode);
        System.Windows.Automation.AutomationProperties.SetItemStatus(this, AppearancePalette.For(darkMode).Name);
    }

    private void SystemPreferenceChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        if (_ready) Dispatcher.BeginInvoke(new Action(ApplyTheme));
    }
    private IntPtr ThemeMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        // Windows broadcasts both messages for app-theme changes. Do not rely on
        // a particular SystemEvents preference category from different OS builds.
        if (_ready && message is 0x001A or 0x031A) Dispatcher.BeginInvoke(new Action(ApplyTheme));
        return IntPtr.Zero;
    }

    public void ActivateFromSecondLaunch(string command)
    {
        if (_settings.IsMinimized) SetMinimized(false, true);
        Show(); WindowState = WindowState.Normal; _settings = _settings with { DesktopMode = false }; ApplyDesktopMode(); EnsureVisible(); SaveSettings(); Activate(); Focus();
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

    private static RectD WorkArea(Forms.Screen screen) => new(screen.WorkingArea.Left, screen.WorkingArea.Top, screen.WorkingArea.Width, screen.WorkingArea.Height);
    private Forms.Screen CurrentScreen()
    {
        var bounds = NativeWindow.Bounds(this);
        return Forms.Screen.FromPoint(new System.Drawing.Point((int)(bounds.X + bounds.Width / 2), (int)(bounds.Y + bounds.Height / 2)));
    }
    private void ApplyInitialPosition() => RestorePlacement(_settings.IsMinimized && !_safeMode);
    private void RestorePlacement(bool orb)
    {
        var placement = orb ? _settings.OrbPlacement : _settings.PanelPlacement;
        var screen = Forms.Screen.AllScreens.FirstOrDefault(x => x.DeviceName == placement?.MonitorId)
            ?? Forms.Screen.PrimaryScreen ?? Forms.Screen.AllScreens[0];
        var bounds = NativeWindow.Bounds(this);
        var area = WorkArea(screen);
        if (area.Width <= 0 || area.Height <= 0) return;
        var target = WindowSnapService.Restore(placement, area, bounds.Width, bounds.Height);
        NativeWindow.Move(this, target.X, target.Y);
    }
    private void EnsureVisible()
    {
        NativeWindow.FitToWorkArea(this);
        var bounds = NativeWindow.Bounds(this);
        if (bounds.Width <= 0 || bounds.Height <= 0) return;
        var area = WorkArea(CurrentScreen());
        if (area.Width <= 0 || area.Height <= 0) return;
        var target = WindowSnapService.ClampToWorkArea(bounds, area, WindowSnapService.DipsToPixels(7, NativeWindow.Dpi(this)));
        NativeWindow.Move(this, target.X, target.Y);
    }
    private void DisplaySettingsChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(new Action(() =>
    {
        if (!_ready) return;
        StopSnap(); EndOrbGesture(false); EnsureVisible(); if (_settings.IsMinimized) SnapOrb(false); SavePosition();
    }));
    private void PowerModeChanged(object sender, PowerModeChangedEventArgs e)
    { if (e.Mode == PowerModes.Resume) Dispatcher.BeginInvoke(new Action(() => { if (_ready) { EnsureVisible(); _toasts?.Rebuild(); } })); }
    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        Dispatcher.BeginInvoke(new Action(() => { if (_ready && !_orbPressed) { EnsureVisible(); if (_settings.IsMinimized) SnapOrb(false); } }));
    }

    private void Render()
    {
        if (_settings.IsMinimized && !_safeMode) return;
        ItemsHost.Children.Clear();
        var showArchive = ArchiveButton.Tag as string == "archive";
        var source = showArchive ? _store.Archived : _store.Items;
        Title = $"{OwnerName}の Todo list";
        NameTitle.Text = $"{OwnerName}の Todo list";
        NameTitle.ToolTip = Title;
        SubTitle.Text = showArchive ? $"已完成 {source.Count} 项" : _store.Items.Count == 0 ? "今天，把一件事做好" : $"还有 {_store.Items.Count} 项待办";
        ArchiveButton.Content = showArchive ? "‹" : "◷";
        if (source.Count == 0)
            ItemsHost.Children.Add(new TextBlock { Text = showArchive ? "还没有已完成的待办" : "暂无待办，点下方 + 添加", Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(4, 14, 4, 14), FontSize = 12, TextAlignment = TextAlignment.Center });
        var limit = showArchive || _showAllItems ? source.Count : Math.Min(10, source.Count);
        foreach (var item in source.Take(limit)) ItemsHost.Children.Add(showArchive ? CreateArchiveRow(item) : CreateTodoRow(item));
        if (!showArchive && source.Count > 10)
        {
            var toggle = new Button { Content = _showAllItems ? "⌃  收起" : $"⌄  还有 {source.Count - 10} 条", Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = (Brush)FindResource("AccentText"), Padding = new Thickness(8, 6, 8, 6), HorizontalContentAlignment = System.Windows.HorizontalAlignment.Left, Cursor = Cursors.Hand };
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
        AnimateTo(PanelWidth, Math.Max(190, Math.Min(640, 130 + visibleCount * 42 + (showArchive ? 25 : 0))), false);
        _toasts?.Rebuild();
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
        var label = new TextBlock { Text = LabelFor(item), Foreground = IsOverdue(item) ? (Brush)FindResource("Urgent") : (Brush)FindResource("AccentText"), FontSize = 10, VerticalAlignment = VerticalAlignment.Center, TextAlignment = TextAlignment.Right, TextTrimming = TextTrimming.CharacterEllipsis };
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
        var undo = new Button { Content = "已完成 · 撤销", Background = Brushes.Transparent, BorderBrush = (Brush)FindResource("AccentText"), Foreground = (Brush)FindResource("AccentText"), Margin = new Thickness(0, 4, 0, 0) };
        undo.Click += (_, _) => { if (_undoTimers.Remove(id, out var t)) t.Stop(); _store.UndoCompletion(id); }; ItemsHost.Children.Insert(0, undo);
    }

    private void AddButton_Click(object sender, RoutedEventArgs e) => StartAdd();
    private void StartAdd() { ActivateFromSecondLaunch("activate"); var editor = new TodoEditorWindow(null) { Owner = this }; if (editor.ShowDialog() == true) { try { _store.Add(editor.TodoText, editor.Priority, editor.Schedule); } catch (ArgumentException ex) { MessageBox.Show(this, ex.Message); } } }
    private void Edit(TodoItem item) { ActivateFromSecondLaunch("activate"); var editor = new TodoEditorWindow(item) { Owner = this }; if (editor.ShowDialog() == true) _store.Update(item.Id, editor.TodoText, editor.Priority, editor.Schedule); }
    private void ArchiveButton_Click(object sender, RoutedEventArgs e) { ArchiveButton.Tag = ArchiveButton.Tag as string == "archive" ? null : "archive"; Render(); }
    private void ClearArchived() { if (_store.Archived.Count > 0 && MessageBox.Show(this, "确定清空全部已完成事项？", "贝卡の Todo list", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes) _store.ClearArchived(); }

    private void CustomizeNameButton_Click(object sender, RoutedEventArgs e) => CustomizeOwnerName();
    private void EnsureOwnerName() { if (_settings.OwnerName is null) CustomizeOwnerName(); }
    private void CustomizeOwnerName() { var dialog = new NameSetupWindow(OwnerName) { Owner = this }; if (dialog.ShowDialog() == true) { var owner = string.IsNullOrWhiteSpace(dialog.OwnerName) ? "贝卡" : dialog.OwnerName[..Math.Min(20, dialog.OwnerName.Length)]; _settings = _settings with { OwnerName = owner }; SaveSettings(); Render(); } }

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || IsInsideButton(e.OriginalSource as DependencyObject)) return;
        try { DragMove(); }
        finally { EnsureVisible(); SavePosition(); }
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
        StopSnap(); EndOrbGesture(false);
        if (_ready) SavePosition();
        _settings = _settings with { IsMinimized = minimized, DesktopMode = minimized && _settings.DesktopMode };
        Panel.Visibility = minimized ? Visibility.Collapsed : Visibility.Visible;
        Orb.Visibility = minimized ? Visibility.Visible : Visibility.Collapsed;
        AnimateTo(minimized ? OrbSize : PanelWidth, minimized ? OrbSize : 190, animate);
        if (!minimized) Render();
        RestorePlacement(minimized);
        if (minimized) SnapOrb(false); else EnsureVisible();
        ApplyDesktopMode(); SavePosition();
    }
    private void AnimateTo(double width, double height, bool animate)
    {
        // Window geometry must never retain a WPF HoldEnd animation. Window and
        // cursor positions are Win32 physical pixels; visual easing is separate.
        foreach (var property in new[] { LeftProperty, TopProperty, WidthProperty, HeightProperty }) BeginAnimation(property, null);
        Width = width; Height = height; Panel.Height = height; UpdateLayout();
        if (_ready) EnsureVisible();
        var surface = _settings.IsMinimized && !_safeMode ? (FrameworkElement)Orb : Panel;
        surface.BeginAnimation(OpacityProperty, null); surface.Opacity = 1;
        if (animate && SystemParameters.ClientAreaAnimation)
            surface.BeginAnimation(OpacityProperty, new DoubleAnimation(.8, 1, TimeSpan.FromMilliseconds(160)) { FillBehavior = FillBehavior.Stop });
    }
    private void Orb_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        StopSnap();
        if (!NativeWindow.TryCursorPosition(out _orbStartMouse)) return;
        var bounds = NativeWindow.Bounds(this);
        _grabX = (_orbStartMouse.X - bounds.X) / Math.Max(1, bounds.Width);
        _grabY = (_orbStartMouse.Y - bounds.Y) / Math.Max(1, bounds.Height);
        _orbDragging = false; _orbPressed = Orb.CaptureMouse(); e.Handled = true;
    }
    private void Orb_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_orbPressed || !Orb.IsMouseCaptured) return;
        if (e.LeftButton != MouseButtonState.Pressed) { EndOrbGesture(true); return; }
        if (!NativeWindow.TryCursorPosition(out var cursor)) return;
        if (Math.Abs(cursor.X - _orbStartMouse.X) + Math.Abs(cursor.Y - _orbStartMouse.Y) > WindowSnapService.DipsToPixels(3, NativeWindow.Dpi(this))) _orbDragging = true;
        if (!_orbDragging) return;
        var bounds = NativeWindow.Bounds(this);
        var screen = Forms.Screen.FromPoint(new System.Drawing.Point(cursor.X, cursor.Y));
        var area = WorkArea(screen);
        if (area.Width <= 0 || area.Height <= 0) return;
        var target = WindowSnapService.ClampToWorkArea(bounds with { X = cursor.X - _grabX * bounds.Width, Y = cursor.Y - _grabY * bounds.Height }, area, 0);
        NativeWindow.Move(this, target.X, target.Y); e.Handled = true;
    }
    private void Orb_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_orbPressed) return;
        var wasDrag = _orbDragging; EndOrbGesture(false);
        if (wasDrag) SnapOrb(true); else SetMinimized(false, true); e.Handled = true;
    }
    private void Orb_LostMouseCapture(object sender, MouseEventArgs e) { if (_orbPressed) EndOrbGesture(true); }
    private void EndOrbGesture(bool snap)
    {
        var pressed = _orbPressed; _orbPressed = false;
        if (Orb.IsMouseCaptured) Orb.ReleaseMouseCapture();
        if (snap && pressed && _settings.IsMinimized) SnapOrb(true);
    }
    private void SnapOrb(bool animate)
    {
        StopSnap();
        var start = NativeWindow.Bounds(this);
        var area = WorkArea(CurrentScreen());
        if (area.Width <= 0 || area.Height <= 0) return;
        var target = WindowSnapService.SnapToNearestEdge(start, area, WindowSnapService.DipsToPixels(7, NativeWindow.Dpi(this)));
        if (animate && SystemParameters.ClientAreaAnimation)
        {
            _motionStart = start; _motionTarget = target; _motionClock.Restart(); _snapTimer.Start();
        }
        else { NativeWindow.Move(this, target.X, target.Y); SavePosition(); }
    }
    private void TickSnap()
    {
        if (_motionStart is not {} start || _motionTarget is not {} target) { StopSnap(); return; }
        var progress = Math.Clamp(_motionClock.Elapsed.TotalMilliseconds / 180, 0, 1);
        var eased = 1 - Math.Pow(1 - progress, 3);
        NativeWindow.Move(this, start.X + (target.X - start.X) * eased, start.Y + (target.Y - start.Y) * eased);
        if (progress >= 1) { StopSnap(); EnsureVisible(); SavePosition(); }
    }
    private void StopSnap() { _snapTimer.Stop(); _motionClock.Stop(); _motionTarget = null; _motionStart = null; }
    private void RecoverWindow()
    {
        Show(); WindowState = WindowState.Normal; StopSnap(); EndOrbGesture(false);
        _settings = _settings with { DesktopMode = false, PanelPlacement = null };
        SetMinimized(false, false); RestorePlacement(false); EnsureVisible(); Activate(); Focus(); SavePosition();
    }

    private void DesktopButton_Click(object sender, RoutedEventArgs e) => ToggleDesktopMode();
    private void ToggleDesktopMode() { _settings = _settings with { DesktopMode = !_settings.DesktopMode }; SaveSettings(); ApplyDesktopMode(); }
    private void ApplyDesktopMode() { if (_safeMode) return; DesktopModeService.Apply(this, _settings.DesktopMode && !_settings.IsMinimized); _tray?.Balloon("贝卡の Todo list", _settings.DesktopMode ? "已沉入桌面：纯展示，鼠标会穿透。" : "已恢复可交互模式。"); }
    private void ToggleStartup() { _startup.SetEnabled(!_startup.IsEnabled); _tray?.Balloon("贝卡の Todo list", _startup.IsEnabled ? "已设为开机自动启动。" : "已关闭开机自动启动。"); }
    private void ToggleVisible() { if (!IsVisible) { Show(); ActivateFromSecondLaunch("activate"); } else Hide(); }
    private void ExportBackup() { var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "LiquidTodo Backup|*.json", FileName = $"LiquidTodo-Backup-{DateTime.Now:yyyyMMdd-HHmmss}.json" }; if (dialog.ShowDialog(this) == true) { _store.Export(dialog.FileName); _tray?.Balloon("导出完成", Path.GetFileName(dialog.FileName)); } }
    private void ImportBackup() { var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "LiquidTodo Backup 或旧版数据|*.json" }; if (dialog.ShowDialog(this) == true) ImportBackup(dialog.FileName); }
    internal void ImportRequestedBackup(string file) => ImportBackup(file);
    private void ImportBackup(string file)
    {
        try { var replace = MessageBox.Show(this, "默认会安全合并并按 UUID 去重。选择“是”可替换本机全部待办（导入前仍会自动备份）。", "导入备份", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes; var result = _store.Import(file, replace ? ImportMode.Replace : ImportMode.Merge); _tray?.Balloon("导入完成", $"新增 {result.ImportedItems + result.ImportedArchived} 项，跳过 {result.SkippedDuplicates} 项。已自动备份。"); } catch (Exception ex) { MessageBox.Show(this, $"无法导入备份：{ex.Message}", "贝卡の Todo list", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private void SaveSettings()
    {
        if (_settingsService.TrySave(_settings, out var error)) { _settingsErrorReported = false; return; }
        if (_settingsErrorReported) return;
        _settingsErrorReported = true;
        if (_tray is not null) _tray.Balloon("设置未保存", "请检查目录权限或磁盘空间，应用仍可继续使用。");
        else MessageBox.Show("设置未保存：" + error, "贝卡の Todo list");
    }
    private void SavePosition()
    {
        var bounds = NativeWindow.Bounds(this);
        if (bounds.Width <= 0 || bounds.Height <= 0) return;
        var screen = CurrentScreen();
        var area = WorkArea(screen);
        if (area.Width <= 0 || area.Height <= 0) return;
        var placement = WindowSnapService.Capture(bounds, area, screen.DeviceName);
        _settings = _settings.IsMinimized && !_safeMode ? _settings with { OrbPlacement = placement } : _settings with { PanelPlacement = placement };
        _settings = _settings with { PlacementVersion = 2, Left = null, Top = null }; SaveSettings();
    }
    protected override void OnLocationChanged(EventArgs e)
    {
        base.OnLocationChanged(e);
        if (!_ready) return;
        _positionSaveTimer.Stop(); _positionSaveTimer.Start();
    }
    protected override void OnKeyDown(System.Windows.Input.KeyEventArgs e) { if (e.Key == Key.Escape && _orbPressed) { EndOrbGesture(true); e.Handled = true; } if (e.Key == Key.N && Keyboard.Modifiers == ModifierKeys.Control) { StartAdd(); e.Handled = true; } base.OnKeyDown(e); }
}
