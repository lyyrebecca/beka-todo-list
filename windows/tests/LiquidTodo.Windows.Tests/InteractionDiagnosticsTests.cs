using System.Reflection;
using LiquidTodo.Core;
using LiquidTodo.Windows.Services;
using Xunit;

namespace LiquidTodo.Windows.Tests;

public sealed class InteractionDiagnosticsTests
{
    [Fact] public void Input_trace_returns_while_diagnostic_writer_is_blocked()
    {
        var root = Path.Combine(Path.GetTempPath(), "ltd-input-log-" + Guid.NewGuid());
        var paths = LiquidTodoPaths.Resolve(["--portable"], root, root);
        var logger = StartupDiagnostics.Create(paths);
        var gate = typeof(StartupDiagnostics).GetField("_gate", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(logger)!;
        using var returned = new ManualResetEventSlim();
        var input = new Thread(() => { logger.WriteInteraction("native-down", "synthetic gesture only"); returned.Set(); }) { IsBackground = true };
        var responded = false;
        Monitor.Enter(gate);
        try
        {
            // A synchronous trace would wait for this exact file-writer gate.
            input.Start();
            responded = returned.Wait(TimeSpan.FromSeconds(2));
        }
        finally { Monitor.Exit(gate); }
        input.Join(TimeSpan.FromSeconds(3));
        Assert.True(responded, "Input hook waited for the diagnostic file writer.");
        Assert.True(SpinWait.SpinUntil(() => File.Exists(logger.LogFile), TimeSpan.FromSeconds(3)));
        // The background writer may still own a short file handle. This is test
        // output in the OS temporary directory, never user's application data.
    }
}
