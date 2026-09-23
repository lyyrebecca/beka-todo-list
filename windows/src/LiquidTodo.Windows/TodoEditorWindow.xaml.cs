using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using LiquidTodo.Core;

namespace LiquidTodo.Windows;

public partial class TodoEditorWindow : Window
{
    private readonly TodoItem? _item;
    public string TodoText => TodoTextBox.Text;
    public TodoPriority Priority => ParseEnum<TodoPriority>(PriorityInput);
    public TodoSchedule? Schedule { get; private set; }
    public TodoEditorWindow(TodoItem? item)
    {
        InitializeComponent(); _item = item; TitleText.Text = item is null ? "新建待办" : "编辑待办";
        var schedule = item?.Schedule;
        TodoTextBox.Text = item?.Text ?? "";
        Select(PriorityInput, item?.Priority ?? TodoPriority.Normal);
        Select(ModeInput, schedule?.Mode ?? TodoTimeMode.None);
        Select(ReminderInput, schedule?.ReminderMode ?? TodoReminderMode.None);
        var date = schedule?.Date?.LocalDateTime ?? DateTime.Now.AddDays(1);
        DateInput.SelectedDate = date.Date; TimeInput.Text = date.ToString("HH:mm");
        StartInput.SelectedDate = schedule?.StartDate?.ToDateTime(TimeOnly.MinValue) ?? DateTime.Today;
        EndInput.SelectedDate = schedule?.EndDate?.ToDateTime(TimeOnly.MinValue) ?? DateTime.Today.AddDays(1);
        if (schedule is { ReminderTimeMinutes: var minute }) TimeInput.Text = $"{minute / 60:00}:{minute % 60:00}";
        Loaded += (_, _) => { TodoTextBox.Focus(); TodoTextBox.SelectAll(); RefreshRows(); };
    }
    private void ModeInput_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (IsLoaded) { var mode = ParseEnum<TodoTimeMode>(ModeInput); if (mode == TodoTimeMode.Period) { Select(ReminderInput, TodoReminderMode.DailyDuringPeriod); TimeInput.Text = "09:00"; } else if (mode != TodoTimeMode.None) Select(ReminderInput, TodoReminderMode.AtTime); RefreshRows(); } }
    private void ReminderInput_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (IsLoaded && ParseEnum<TodoReminderMode>(ReminderInput) == TodoReminderMode.DayBefore) TimeInput.Text = "21:00"; }
    private void RefreshRows() { var mode = ParseEnum<TodoTimeMode>(ModeInput); DateRow.Visibility = mode is TodoTimeMode.Deadline or TodoTimeMode.Day ? Visibility.Visible : Visibility.Collapsed; PeriodRow.Visibility = mode == TodoTimeMode.Period ? Visibility.Visible : Visibility.Collapsed; ReminderRow.Visibility = mode == TodoTimeMode.None ? Visibility.Collapsed : Visibility.Visible; DateLabel.Text = mode == TodoTimeMode.Day ? "某一天" : "日期和时间"; }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(TodoText)) { MessageBox.Show(this, "待办内容不能为空。", "贝卡の Todo list", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var mode = ParseEnum<TodoTimeMode>(ModeInput); var reminder = ParseEnum<TodoReminderMode>(ReminderInput);
        if (!TimeOnly.TryParseExact(TimeInput.Text.Trim(), "H:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var time) && !TimeOnly.TryParse(TimeInput.Text.Trim(), out time)) { MessageBox.Show(this, "提醒时间请使用 HH:mm，例如 21:00。", "贝卡の Todo list"); return; }
        if (mode == TodoTimeMode.None) Schedule = null;
        else if (mode == TodoTimeMode.Period)
        {
            var start = DateOnly.FromDateTime(StartInput.SelectedDate ?? DateTime.Today); var end = DateOnly.FromDateTime(EndInput.SelectedDate ?? DateTime.Today);
            Schedule = new TodoSchedule(mode, null, start, end, reminder == TodoReminderMode.None ? TodoReminderMode.None : TodoReminderMode.DailyDuringPeriod, time.Hour * 60 + time.Minute).Normalize();
        }
        else
        {
            var day = (DateInput.SelectedDate ?? DateTime.Today).Date.Add(time.ToTimeSpan());
            Schedule = new TodoSchedule(mode, new DateTimeOffset(day), null, null, reminder is TodoReminderMode.DayBefore or TodoReminderMode.None ? reminder : TodoReminderMode.AtTime, time.Hour * 60 + time.Minute);
        }
        DialogResult = true;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
    private static void Select(System.Windows.Controls.ComboBox box, Enum value) => box.SelectedItem = box.Items.Cast<ComboBoxItem>().First(x => string.Equals(x.Tag?.ToString(), value.ToString(), StringComparison.OrdinalIgnoreCase));
    private static T ParseEnum<T>(System.Windows.Controls.ComboBox box) where T : struct, Enum => Enum.Parse<T>(((ComboBoxItem)box.SelectedItem).Tag!.ToString()!, true);
}
