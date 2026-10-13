namespace LiquidTodo.Core;

// Reading surfaces are deliberately tinted, never white overlays on transparent
// desktop text. These palettes are shared with contrast and theme regression tests.
public sealed record AppearancePalette(
    string Name, string FillTop, string FillBottom, string RowFill, string Ink,
    string Muted, string SecondaryInk, string Accent, string AccentInk,
    string Important, string Urgent, string Surface, string AccentText, string InputFill, string InputBorder)
{
    public const string OrbGlyph = "干"; // U+5E72, native text; never an AI bitmap.
    public static AppearancePalette Day { get; } = new(
        "白天 · 轻雾紫", "CDC0E8", "BFAEDC", "CCBEE5", "403050",
        "503D5C", "503D5C", "7E63C0", "FFFFFF", "704914", "8B2D47", "E7DEF2", "60437E", "E3D8F2", "A58CBC");
    public static AppearancePalette Night { get; } = new(
        "夜间 · 烟紫玻璃", "79678E", "695879", "5E4D70", "F8F1FF",
        "F8F1FF", "F8F1FF", "AF99E3", "30203F", "FFDF8E", "FFC1CF", "31283E", "E2D0FF", "473852", "A58DBC");
    public static AppearancePalette For(bool dark) => dark ? Night : Day;
}
