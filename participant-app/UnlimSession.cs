using System.Diagnostics;
using System.Text;

namespace PalworldJoin;

internal sealed class UnlimSession : IDisposable
{
    private Process? process;
    internal event Action<string>? OutputReceived;
    internal event Action? Exited;
    internal bool IsRunning => process is { HasExited: false };

    internal void Connect(string key)
    {
        if (IsRunning) throw new InvalidOperationException("すでに接続処理が動作しています。");
        var info = new ProcessStartInfo(AppPaths.UnlimExecutable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        info.ArgumentList.Add("--connect");
        info.ArgumentList.Add(key);
        info.ArgumentList.Add("--no-tui");
        info.ArgumentList.Add("--log");
        process = new Process { StartInfo = info, EnableRaisingEvents = true };
        process.OutputDataReceived += OnOutput;
        process.ErrorDataReceived += OnOutput;
        process.Exited += (_, _) => Exited?.Invoke();
        if (!process.Start()) throw new InvalidOperationException("Unlimを起動できません。");
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
    }

    private void OnOutput(object sender, DataReceivedEventArgs args)
    {
        if (!string.IsNullOrWhiteSpace(args.Data)) OutputReceived?.Invoke(args.Data);
    }

    internal void Disconnect()
    {
        if (process is { HasExited: false })
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            try { process.WaitForExit(3000); } catch { }
        }
        process?.Dispose();
        process = null;
    }

    public void Dispose() => Disconnect();
}
