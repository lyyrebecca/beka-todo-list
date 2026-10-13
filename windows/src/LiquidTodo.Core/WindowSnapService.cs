namespace LiquidTodo.Core;

public static class WindowSnapService
{
    public static RectD SnapToNearestEdge(RectD orb, RectD workArea, double margin = 7)
    {
        var bounded = ClampToWorkArea(orb, workArea, margin);
        var padding = EffectiveMargin(workArea, bounded, margin);
        var x = bounded.CenterX < workArea.CenterX ? workArea.X + padding : workArea.Right - bounded.Width - padding;
        return bounded with { X = x };
    }

    // Every input here is in physical screen pixels, including negative origins.
    public static RectD ClampToWorkArea(RectD window, RectD area, double margin = 7)
    {
        if (!double.IsFinite(area.X) || !double.IsFinite(area.Y) || !double.IsFinite(area.Width) || !double.IsFinite(area.Height) || area.Width <= 0 || area.Height <= 0)
            throw new ArgumentOutOfRangeException(nameof(area));
        var width = Math.Min(area.Width, double.IsFinite(window.Width) && window.Width > 0 ? window.Width : 48);
        var height = Math.Min(area.Height, double.IsFinite(window.Height) && window.Height > 0 ? window.Height : 48);
        var sized = new RectD(window.X, window.Y, width, height);
        var pad = EffectiveMargin(area, sized, margin);
        var x = double.IsFinite(window.X) ? window.X : area.Right - width - pad;
        var y = double.IsFinite(window.Y) ? window.Y : area.Y + (area.Height - height) / 2;
        return new(Math.Clamp(x, area.X + pad, area.Right - width - pad), Math.Clamp(y, area.Y + pad, area.Bottom - height - pad), width, height);
    }

    private static double EffectiveMargin(RectD area, RectD window, double margin) =>
        Math.Min(double.IsFinite(margin) ? Math.Max(0, margin) : 7, Math.Max(0, Math.Min(area.Width - window.Width, area.Height - window.Height) / 2));

    public static double DipsToPixels(double dips, double dpi) => dips * (double.IsFinite(dpi) && dpi > 0 ? dpi : 96) / 96;

    public static WindowPlacement Capture(RectD window, RectD area, string monitorId)
    {
        var bounded = ClampToWorkArea(window, area, 0);
        return new(monitorId, (bounded.X - area.X) / Math.Max(1, area.Width - bounded.Width), (bounded.Y - area.Y) / Math.Max(1, area.Height - bounded.Height));
    }

    public static RectD Restore(WindowPlacement? placement, RectD area, double width, double height)
    {
        static double Ratio(double? value, double fallback) => value is {} v && double.IsFinite(v) ? Math.Clamp(v, 0, 1) : fallback;
        return ClampToWorkArea(new(area.X + Ratio(placement?.Horizontal, 1) * Math.Max(0, area.Width - width),
            area.Y + Ratio(placement?.Vertical, .5) * Math.Max(0, area.Height - height), width, height), area);
    }
}

public sealed record WindowPlacement(string MonitorId, double Horizontal, double Vertical);
