namespace LiquidTodo.Core;

public static class WindowSnapService
{
    public static RectD SnapToNearestEdge(RectD orb, RectD workArea, double margin = 7)
    {
        var x = orb.CenterX < workArea.CenterX ? workArea.X + margin : workArea.Right - orb.Width - margin;
        var y = Math.Clamp(orb.Y, workArea.Y + margin, workArea.Bottom - orb.Height - margin);
        return new RectD(x, y, orb.Width, orb.Height);
    }
}
