using System.Windows;
namespace LiquidTodo.Windows;
public partial class NameSetupWindow : Window
{
    public string OwnerName => NameInput.Text.Trim();
    public NameSetupWindow(string currentName) { InitializeComponent(); NameInput.Text = currentName; Loaded += (_, _) => { NameInput.Focus(); NameInput.SelectAll(); }; }
    private void Default_Click(object sender, RoutedEventArgs e) { NameInput.Text = "贝卡"; DialogResult = true; }
    private void Save_Click(object sender, RoutedEventArgs e) => DialogResult = true;
}
