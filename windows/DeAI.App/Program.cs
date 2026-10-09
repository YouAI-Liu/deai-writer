using System;
using System.Threading;
using System.Windows;

namespace DeAI.App;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        System.Windows.Forms.Application.SetHighDpiMode(System.Windows.Forms.HighDpiMode.PerMonitorV2);
        using var mutex = new Mutex(true, "Local\\DeAI.Windows", out var first);
        if (!first) { MessageBox.Show("DeAI 已在托盘运行 / Already running in the system tray."); return; }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        Controller? controller = null;
        app.Startup += (_, _) =>
        {
            try { controller = new Controller(); controller.Start(); }
            catch (Exception error) { Ui.Error(error); app.Shutdown(1); }
        };
        app.Exit += (_, _) => controller?.Dispose();
        app.Run();
    }
}
