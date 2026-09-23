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
        var reminderMinute = schedule?.ReminderTimeMinutes ?? 1260;
        ReminderTimeInput.Text = $"{reminderMinute / 60:00}:{reminderMinute % 60:00}";
        Loaded += (_, _) => { TodoTextBox.Focus(); TodoTextBox.SelectAll(); ConfigureReminderOptions(ParseEnum<TodoTimeMode>(ModeInput)); RefreshRows(); };
    }
    private void ModeInput_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded) return;
        var mode = ParseEnum<TodoTimeMode>(ModeInput);
        if (mode == TodoTimeMode.Period)
        {
            Select(ReminderInput, TodoReminderMode.DailyDuringPeriod);
            ReminderTimeInput.Text = "09:00";
        }
        else if (mode != TodoTimeMode.None)
        {
            Select(ReminderInput, TodoReminderMode.AtTime);
        }
        ConfigureReminderOptions(mode);
        RefreshRows();
    }

    private void ReminderInput_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded) return;
        var reminder = ParseEnum<TodoReminderMode>(ReminderInput);
        if (reminder == TodoReminderMode.DayBefore) ReminderTimeInput.Text = "21:00";
        else if (reminder == TodoReminderMode.DailyDuringPeriod) ReminderTimeInput.Text = "09:00";
        RefreshRows();
    }

    private void ConfigureReminderOptions(TodoTimeMode mode)
    {
        foreach (ComboBoxItem option in ReminderInput.Items)
        {
            var value = Enum.Parse<TodoReminderMode>(option.Tag!.ToString()!, true);
            option.Visibility = mode == TodoTimeMode.Period
                ? value is TodoReminderMode.None or TodoReminderMode.DailyDuringPeriod ? Visibility.Visible : Visibility.Collapsed
                : value is TodoReminderMode.None or TodoReminderMode.AtTime or TodoReminderMode.DayBefore ? Visibility.Visible : Visibility.Collapsed;
        }
        var selected = ParseEnum<TodoReminderMode>(ReminderInput);
        if ((mode == TodoTimeMode.Period && selected is not (TodoReminderMode.None or TodoReminderMode.DailyDuringPeriod)) ||
            (mode != TodoTimeMode.Period && selected == TodoReminderMode.DailyDuringPeriod))
            Select(ReminderInput, mode == TodoTimeMode.Period ? TodoReminderMode.DailyDuringPeriod : TodoReminderMode.AtTime);
    }

    private void RefreshRows()
    {
        var mode = ParseEnum<TodoTimeMode>(ModeInput);
        var reminder = ParseEnum<TodoReminderMode>(ReminderInput);
        DateRow.Visibility = mode is TodoTimeMode.Deadline or TodoTimeMode.Day ? Visibility.Visible : Visibility.Collapsed;
        PeriodRow.Visibility = mode == TodoTimeMode.Period ? Visibility.Visible : Visibility.Collapsed;
        ReminderRow.Visibility = mode == TodoTimeMode.None ? Visibility.Collapsed : Visibility.Visible;
        ReminderTimeRow.Visibility = reminder is TodoReminderMode.DayBefore or TodoReminderMode.DailyDuringPeriod ? Visibility.Visible : Visibility.Collapsed;
        ReminderTimeLabel.Text = reminder == TodoReminderMode.DayBefore ? "提前一天" : "每天提醒";
        DateLabel.Text = mode == TodoTimeMode.Day ? "某一天" : "截止日期";
    }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(TodoText)) { MessageBox.Show(this, "待办内容不能为空。", "贝卡の Todo list", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var mode = ParseEnum<TodoTimeMode>(ModeInput); var reminder = ParseEnum<TodoReminderMode>(ReminderInput);
        var usesReminderClock = reminder is TodoReminderMode.DayBefore or TodoReminderMode.DailyDuringPeriod;
        var timeText = mode == TodoTimeMode.Period ? ReminderTimeInput.Text : TimeInput.Text;
        if (mode != TodoTimeMode.None && (mode == TodoTimeMode.Period ? reminder == TodoReminderMode.DailyDuringPeriod : true) && !TryParseTime(timeText, out _))
        { MessageBox.Show(this, mode == TodoTimeMode.Period ? "每日提醒时间请使用 HH:mm，例如 09:00。" : "日期时间请使用 HH:mm，例如 21:00。", "贝卡の Todo list"); return; }
        var reminderMinutes = 1260;
        if (usesReminderClock)
        {
            if (!TryParseTime(ReminderTimeInput.Text, out var reminderTime)) { MessageBox.Show(this, "提醒时间请使用 HH:mm，例如 21:00。", "贝卡の Todo list"); return; }
            reminderMinutes = reminderTime.Hour * 60 + reminderTime.Minute;
        }
        if (mode == TodoTimeMode.None) Schedule = null;
        else if (mode == TodoTimeMode.Period)
        {
            var start = DateOnly.FromDateTime(StartInput.SelectedDate ?? DateTime.Today); var end = DateOnly.FromDateTime(EndInput.SelectedDate ?? DateTime.Today);
            var dailyTime = reminder == TodoReminderMode.DailyDuringPeriod && TryParseTime(ReminderTimeInput.Text, out var periodTime) ? periodTime.Hour * 60 + periodTime.Minute : 1260;
            Schedule = new TodoSchedule(mode, null, start, end, reminder == TodoReminderMode.None ? TodoReminderMode.None : TodoReminderMode.DailyDuringPeriod, dailyTime).Normalize();
        }
        else
        {
            if (!TryParseTime(TimeInput.Text, out var time)) { MessageBox.Show(this, "日期时间请使用 HH:mm，例如 21:00。", "贝卡の Todo list"); return; }
            var day = (DateInput.SelectedDate ?? DateTime.Today).Date.Add(time.ToTimeSpan());
            Schedule = new TodoSchedule(mode, new DateTimeOffset(day), null, null, reminder is TodoReminderMode.DayBefore or TodoReminderMode.None ? reminder : TodoReminderMode.AtTime, reminderMinutes);
        }
        DialogResult = true;
    }

    private static bool TryParseTime(string? value, out TimeOnly time) =>
        TimeOnly.TryParseExact(value?.Trim(), ["H:mm", "HH:mm"], CultureInfo.InvariantCulture, DateTimeStyles.None, out time);
    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
    private static void Select(System.Windows.Controls.ComboBox box, Enum value) => box.SelectedItem = box.Items.Cast<ComboBoxItem>().First(x => string.Equals(x.Tag?.ToString(), value.ToString(), StringComparison.OrdinalIgnoreCase));
    private static T ParseEnum<T>(System.Windows.Controls.ComboBox box) where T : struct, Enum => Enum.Parse<T>(((ComboBoxItem)box.SelectedItem).Tag!.ToString()!, true);
}
