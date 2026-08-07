using System.Diagnostics;
using System.ComponentModel;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace PalworldUnlimClient;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(true, "Local\\PalworldUnlimParticipantClient", out var firstInstance);
        if (!firstInstance)
        {
            MessageBox.Show("Palworld参加アプリはすでに起動しています。", "Palworld Unlim Client",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

internal sealed class MainForm : Form
{
    private const int DefaultGamePort = 8211;
    private static readonly Regex LocalPortPattern = new(
        @"(?:localhost|127\.0\.0\.1)\s*[:=\-]>?\s*(?<port>\d{2,5})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex KeyPattern = new(@"^[A-Za-z0-9_-]{8,200}$", RegexOptions.Compiled);

    private readonly string appDataDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PalworldUnlimClient");
    private readonly TextBox keyBox = new();
    private readonly TextBox addressBox = new();
    private readonly Label statusLabel = new();
    private readonly Label versionLabel = new();
    private readonly Button connectButton = new();
    private readonly Button disconnectButton = new();
    private readonly Button updateButton = new();
    private readonly Button repairButton = new();
    private Process? unlimProcess;
    private bool closing;

    private string SettingsPath => Path.Combine(appDataDirectory, "settings.json");
    private string LogPath => Path.Combine(appDataDirectory, "unlim-client.log");
    private string DiagnosticLogPath => Path.Combine(appDataDirectory, "app-diagnostics.log");

    public MainForm()
    {
        Directory.CreateDirectory(appDataDirectory);
        Text = "Palworld Unlim Client";
        ClientSize = new Size(600, 430);
        MinimumSize = new Size(600, 430);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Yu Gothic UI", 10F);
        BackColor = Color.FromArgb(246, 247, 249);
        FormClosing += OnFormClosing;

        var title = MakeLabel("Palworld サーバーに参加", 28, 23, 18F, FontStyle.Bold);
        var description = MakeLabel("Discordの接続キーを貼り付けて、接続ボタンを押してください。", 31, 67, 10F);
        description.ForeColor = Color.DimGray;
        Controls.AddRange([title, description, MakeLabel("接続キー", 31, 108)]);

        keyBox.SetBounds(34, 134, 528, 31);
        keyBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        Controls.Add(keyBox);

        ConfigureButton(connectButton, "接続", 34, 184, 150, Color.FromArgb(36, 104, 214), Color.White);
        ConfigureButton(disconnectButton, "切断", 194, 184, 110, SystemColors.Control, Color.Black);
        ConfigureButton(updateButton, "Unlimを更新", 314, 184, 150, SystemColors.Control, Color.Black);
        ConfigureButton(repairButton, "環境修復", 474, 184, 88, SystemColors.Control, Color.Black);
        disconnectButton.Enabled = false;
        connectButton.Click += async (_, _) => await ConnectAsync();
        disconnectButton.Click += (_, _) => Disconnect();
        updateButton.Click += async (_, _) => await InstallOrUpdateAsync();
        repairButton.Click += async (_, _) => await RepairEnvironmentAsync();

        Controls.AddRange([connectButton, disconnectButton, updateButton, repairButton]);
        Controls.Add(MakeLabel("状態", 31, 253));
        statusLabel.SetBounds(94, 253, 465, 24);
        statusLabel.Text = "未接続";
        statusLabel.ForeColor = Color.DimGray;
        Controls.Add(statusLabel);

        Controls.Add(MakeLabel("Palworldの接続先", 31, 296));
        addressBox.SetBounds(34, 323, 380, 31);
        addressBox.Text = "127.0.0.1:8211";
        addressBox.ReadOnly = true;
        Controls.Add(addressBox);

        var copyButton = new Button { Text = "コピー" };
        copyButton.SetBounds(424, 321, 90, 35);
        copyButton.Click += (_, _) => Clipboard.SetText(addressBox.Text);
        Controls.Add(copyButton);

        versionLabel.SetBounds(34, 384, 190, 23);
        versionLabel.Text = "Unlim: 確認中";
        versionLabel.ForeColor = Color.DimGray;
        Controls.Add(versionLabel);

        var portNote = MakeLabel("8989はPalworldの接続ポートではありません。", 224, 384, 9F);
        portNote.ForeColor = Color.DimGray;
        Controls.Add(portNote);

        LoadSettings();
        _ = RefreshVersionAsync();
    }

    private Label MakeLabel(string text, int x, int y, float size = 10F, FontStyle style = FontStyle.Regular)
    {
        return new Label
        {
            Text = text,
            AutoSize = true,
            Location = new Point(x, y),
            Font = new Font("Yu Gothic UI", size, style)
        };
    }

    private static void ConfigureButton(Button button, string text, int x, int y, int width,
        Color backColor, Color foreColor)
    {
        button.Text = text;
        button.SetBounds(x, y, width, 43);
        button.BackColor = backColor;
        button.ForeColor = foreColor;
        button.FlatStyle = FlatStyle.Flat;
    }

    private string? FindUnlim()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Unlim", "unlim.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "unlim", "bin", "unlim.exe")
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    private IReadOnlyList<Process> FindOtherUnlimProcesses()
    {
        var childId = unlimProcess is { HasExited: false } ? unlimProcess.Id : -1;
        var result = new List<Process>();
        foreach (var process in Process.GetProcessesByName("unlim"))
        {
            try
            {
                process.Refresh();
                if (process.Id != childId && !process.HasExited) result.Add(process);
                else process.Dispose();
            }
            catch
            {
                process.Dispose();
            }
        }
        return result;
    }

    private string DescribeProcess(Process process)
    {
        var path = "実行場所を確認できません（管理者権限で起動している可能性）";
        try { path = process.MainModule?.FileName ?? path; } catch { }
        return $"PID {process.Id}: {path}";
    }

    private bool ResolveUnlimProcessConflict(string operation)
    {
        var processes = FindOtherUnlimProcesses();
        if (processes.Count == 0) return true;

        Thread.Sleep(250);
        var liveProcesses = processes.Where(process =>
        {
            try { process.Refresh(); return !process.HasExited; } catch { return false; }
        }).ToArray();
        foreach (var ended in processes.Except(liveProcesses)) ended.Dispose();
        if (liveProcesses.Length == 0) return true;

        var details = string.Join(Environment.NewLine, liveProcesses.Select(DescribeProcess));
        WriteDiagnostic($"Detected Unlim process conflict during {operation}:{Environment.NewLine}{details}");

        var answer = MessageBox.Show(
            $"別のUnlimアプリまたはCLIが{liveProcesses.Length}個起動しています。\n" +
            $"このままでは{operation}できません。既存のUnlimを終了しますか？\n\n" +
            $"{details}\n\n" +
            "ホストとしてUnlimを使用しているPCでは［いいえ］を選んでください。",
            "Unlimがすでに起動しています", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (answer != DialogResult.Yes)
        {
            foreach (var process in liveProcesses) process.Dispose();
            return false;
        }

        foreach (var process in liveProcesses)
        {
            try
            {
                if (process.HasExited) continue;
                if (process.MainWindowHandle != IntPtr.Zero)
                {
                    process.CloseMainWindow();
                    if (process.WaitForExit(2500)) continue;
                }
                process.Kill(entireProcessTree: true);
                process.WaitForExit(3000);
            }
            catch (Exception exception) when (exception is Win32Exception or InvalidOperationException)
            {
                ShowOperationError("既存のUnlimを終了できませんでした。", exception,
                    "Unlimが管理者権限で動作している可能性があります。タスクマネージャーを管理者として開いてUnlimを終了するか、この参加アプリを右クリックして［管理者として実行］してください。");
                return false;
            }
            finally
            {
                process.Dispose();
            }
        }

        if (FindOtherUnlimProcesses().Count > 0)
        {
            MessageBox.Show("Unlimがまだ動作しています。タスクマネージャーから終了して、もう一度お試しください。",
                Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        return true;
    }

    private async Task RepairEnvironmentAsync()
    {
        if (unlimProcess is { HasExited: false })
        {
            MessageBox.Show("先に［切断］を押してください。", Text,
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var cliDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Unlim");
        var guiDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "unlim");
        var existing = new[] { cliDirectory, guiDirectory }.Where(Directory.Exists).ToArray();
        var detected = FindOtherUnlimProcesses();
        var processDescription = detected.Count == 0
            ? "起動中のUnlimは検出されませんでした。"
            : string.Join(Environment.NewLine, detected.Select(DescribeProcess));
        foreach (var process in detected) process.Dispose();
        var folderDescription = existing.Length == 0
            ? "残存フォルダーは検出されませんでした。"
            : string.Join(Environment.NewLine, existing);

        var answer = MessageBox.Show(
            "Unlim環境を修復します。\n\n" +
            $"検出プロセス:\n{processDescription}\n\n検出フォルダー:\n{folderDescription}\n\n" +
            "起動中のUnlimを終了し、上記のUnlim専用フォルダーを削除してから公式版を再インストールします。続行しますか？",
            "Unlim環境修復", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (answer != DialogResult.Yes) return;

        SetBusy(true);
        SetStatus("Unlim環境を修復しています…", Color.DarkOrange);
        try
        {
            if (!ResolveUnlimProcessConflict("環境修復")) return;
            DeleteUnlimDirectory(cliDirectory,
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
            DeleteUnlimDirectory(guiDirectory,
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));
            WriteDiagnostic("Removed detected Unlim installation remnants.");
            SetStatus("残存環境を削除しました。公式版を再導入します…", Color.DarkOrange);
        }
        catch (Exception exception)
        {
            WriteDiagnostic($"Environment repair failed: {exception}");
            SetStatus("環境修復に失敗しました。", Color.Firebrick);
            ShowOperationError("Unlimの残存環境を削除できませんでした。", exception);
            return;
        }
        finally
        {
            SetBusy(false);
        }

        await InstallOrUpdateAsync();
    }

    private static void DeleteUnlimDirectory(string target, string expectedParent)
    {
        var fullTarget = Path.GetFullPath(target).TrimEnd(Path.DirectorySeparatorChar);
        var fullParent = Path.GetFullPath(expectedParent).TrimEnd(Path.DirectorySeparatorChar);
        if (!string.Equals(Path.GetDirectoryName(fullTarget), fullParent,
                StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(Path.GetFileName(fullTarget), "Unlim", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"安全確認に失敗したため削除しませんでした: {fullTarget}");
        if (Directory.Exists(fullTarget)) Directory.Delete(fullTarget, recursive: true);
    }

    private void WriteDiagnostic(string message)
    {
        try
        {
            File.AppendAllText(DiagnosticLogPath,
                $"[{DateTimeOffset.Now:O}] {message}{Environment.NewLine}", Encoding.UTF8);
        }
        catch { }
    }

    private async Task RefreshVersionAsync()
    {
        var executable = FindUnlim();
        if (executable is null)
        {
            versionLabel.Text = "Unlim: 未インストール";
            return;
        }

        try
        {
            using var process = StartProcess(executable, "--version", redirect: true);
            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            versionLabel.Text = $"Unlim: {output.Trim().Split('\n').LastOrDefault()?.Trim()}";
        }
        catch
        {
            versionLabel.Text = "Unlim: 確認失敗";
        }
    }

    private async Task InstallOrUpdateAsync()
    {
        if (unlimProcess is { HasExited: false })
        {
            MessageBox.Show("接続を切断してから更新してください。", Text,
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (!ResolveUnlimProcessConflict("更新")) return;

        SetBusy(true);
        SetStatus("Unlimを公式配布元から更新しています…", Color.DarkOrange);
        try
        {
            using var client = new HttpClient();
            client.DefaultRequestHeaders.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue
            {
                NoCache = true,
                NoStore = true
            };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("PalworldUnlimClient/0.1.3");

            var cacheBust = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            using var manifestResponse = await client.GetAsync($"https://api.zpw.jp/unlimmap?cachebust={cacheBust}");
            manifestResponse.EnsureSuccessStatusCode();
            await using var manifestStream = await manifestResponse.Content.ReadAsStreamAsync();
            using var manifest = await JsonDocument.ParseAsync(manifestStream);

            var root = manifest.RootElement;
            var version = root.GetProperty("version").GetString();
            var downloadUrl = root.GetProperty("downloads").GetProperty("windows_amd64").GetString();
            var hashInfo = root.GetProperty("hashes").GetProperty("windows_amd64");
            var expectedHash = hashInfo.GetProperty("sha256").GetString()?.ToLowerInvariant();
            var expectedSize = hashInfo.GetProperty("size").GetInt64();
            if (string.IsNullOrWhiteSpace(version) || string.IsNullOrWhiteSpace(downloadUrl) ||
                string.IsNullOrWhiteSpace(expectedHash) || expectedHash.Length != 64 || expectedSize <= 0)
                throw new InvalidOperationException("Unlim公式APIの配布情報が不完全です。");

            var separator = downloadUrl.Contains('?') ? '&' : '?';
            var verifiedDownloadUrl = $"{downloadUrl}{separator}cachebust={cacheBust}";
            var installDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Unlim");
            var destination = Path.Combine(installDirectory, "unlim.exe");
            var staging = Path.Combine(appDataDirectory, $"unlim-{version}.download");

            try
            {
                using var downloadResponse = await client.GetAsync(verifiedDownloadUrl,
                    HttpCompletionOption.ResponseHeadersRead);
                downloadResponse.EnsureSuccessStatusCode();
                await using (var source = await downloadResponse.Content.ReadAsStreamAsync())
                await using (var target = new FileStream(staging, FileMode.Create, FileAccess.Write, FileShare.None))
                    await source.CopyToAsync(target);

                var actualSize = new FileInfo(staging).Length;
                if (actualSize != expectedSize)
                    throw new InvalidOperationException(
                        $"ダウンロードサイズが公式値と一致しません（期待: {expectedSize}, 実際: {actualSize}）。");

                await using var verificationStream = File.OpenRead(staging);
                var actualHash = Convert.ToHexString(await SHA256.HashDataAsync(verificationStream)).ToLowerInvariant();
                if (!CryptographicOperations.FixedTimeEquals(
                        Encoding.ASCII.GetBytes(actualHash), Encoding.ASCII.GetBytes(expectedHash)))
                    throw new InvalidOperationException(
                        $"SHA-256が公式値と一致しません。\n期待: {expectedHash}\n実際: {actualHash}");

                Directory.CreateDirectory(installDirectory);
                File.Move(staging, destination, overwrite: true);
            }
            finally
            {
                if (File.Exists(staging)) File.Delete(staging);
            }

            await RefreshVersionAsync();
            var installed = FindUnlim();
            if (installed is null || !File.Exists(installed))
                throw new InvalidOperationException("更新直後にUnlimが見つかりません。Windows Defenderが隔離した可能性があります。");
            SetStatus($"Unlim {version}への更新が完了しました。", Color.SeaGreen);
            WriteDiagnostic($"Installed and verified Unlim {version}.");
        }
        catch (Exception exception)
        {
            WriteDiagnostic($"Unlim update failed: {exception}");
            SetStatus("更新に失敗しました。", Color.Firebrick);
            ShowOperationError("Unlimを更新できませんでした。", exception);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task ConnectAsync()
    {
        var key = keyBox.Text.Trim();
        if (!KeyPattern.IsMatch(key))
        {
            MessageBox.Show("Discordに掲載された正しい接続キーを入力してください。", Text,
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var executable = FindUnlim();
        if (executable is null)
        {
            if (MessageBox.Show("Unlimがありません。今すぐ公式版をインストールしますか？", Text,
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                await InstallOrUpdateAsync();
            executable = FindUnlim();
            if (executable is null) return;
        }
        if (!ResolveUnlimProcessConflict("接続")) return;

        SaveSettings(key);
        File.WriteAllText(LogPath, string.Empty, new UTF8Encoding(true));
        addressBox.Text = "127.0.0.1:8211";

        try
        {
            var info = new ProcessStartInfo(executable)
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

            unlimProcess = new Process { StartInfo = info, EnableRaisingEvents = true };
            unlimProcess.OutputDataReceived += OnUnlimOutput;
            unlimProcess.ErrorDataReceived += OnUnlimOutput;
            unlimProcess.Exited += (_, _) => BeginInvoke(() => OnDisconnectedUnexpectedly());
            if (!unlimProcess.Start()) throw new InvalidOperationException("Unlimを起動できませんでした。");
            unlimProcess.BeginOutputReadLine();
            unlimProcess.BeginErrorReadLine();

            connectButton.Enabled = false;
            disconnectButton.Enabled = true;
            updateButton.Enabled = false;
            SetStatus("接続処理中です。数秒お待ちください…", Color.DarkOrange);
        }
        catch (Exception exception)
        {
            SetStatus("接続に失敗しました。", Color.Firebrick);
            ShowOperationError("Unlimへ接続できませんでした。", exception);
        }
    }

    private void ShowOperationError(string heading, Exception exception, string? guidance = null)
    {
        var detail = guidance ?? exception switch
        {
            UnauthorizedAccessException =>
                "ファイルを変更する権限がありません。起動中のUnlimを終了してください。解決しない場合は、この参加アプリを右クリックして［管理者として実行］してください。",
            IOException when exception.Message.Contains("being used", StringComparison.OrdinalIgnoreCase) ||
                             exception.Message.Contains("使用", StringComparison.OrdinalIgnoreCase) =>
                "Unlimのファイルが使用中です。GUI版とCLI版をすべて終了し、タスクマネージャーにunlim.exeが残っていないことを確認してください。",
            HttpRequestException =>
                "公式配布サーバーへ接続できませんでした。インターネット接続、VPN、プロキシ、セキュリティソフトを確認してから再試行してください。",
            CryptographicException =>
                "ダウンロードしたファイルの安全性を確認できなかったため、置き換えを中止しました。検証を無効にせず、時間を置いて再試行してください。",
            Win32Exception win32 when win32.NativeErrorCode is 5 or 740 =>
                "Windowsに操作を拒否されました。Unlimを終了し、この参加アプリを右クリックして［管理者として実行］してください。",
            _ when exception.Message.Contains("SHA-256", StringComparison.OrdinalIgnoreCase) =>
                "公式情報とファイルが一致しないため、安全のため更新を中止しました。時間を置いて再試行してください。",
            _ => "アプリを再起動してもう一度お試しください。"
        };

        MessageBox.Show($"{heading}\n\n{detail}\n\n詳細:\n{exception.Message}\n\n" +
                        $"接続ログ: {LogPath}\n診断ログ: {DiagnosticLogPath}", Text,
            MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private void OnUnlimOutput(object sender, DataReceivedEventArgs eventArgs)
    {
        if (string.IsNullOrWhiteSpace(eventArgs.Data)) return;
        try { File.AppendAllText(LogPath, eventArgs.Data + Environment.NewLine, Encoding.UTF8); } catch { }

        var line = eventArgs.Data;
        BeginInvoke(() =>
        {
            var lowered = line.ToLowerInvariant();
            if (lowered.Contains("connected") || lowered.Contains("connection established"))
                SetStatus("接続しました。Palworldを起動してください。", Color.SeaGreen);

            if (!lowered.Contains("8211") && !lowered.Contains("mapping") && !lowered.Contains("listener")) return;
            foreach (Match match in LocalPortPattern.Matches(line))
            {
                if (!int.TryParse(match.Groups["port"].Value, out var port) || port is 8989 or 9800) continue;
                addressBox.Text = $"127.0.0.1:{port}";
            }
        });
    }

    private void Disconnect()
    {
        if (unlimProcess is { HasExited: false })
        {
            try { unlimProcess.Kill(entireProcessTree: true); } catch { }
            try { unlimProcess.WaitForExit(3000); } catch { }
        }
        unlimProcess?.Dispose();
        unlimProcess = null;
        connectButton.Enabled = true;
        disconnectButton.Enabled = false;
        updateButton.Enabled = true;
        repairButton.Enabled = true;
        SetStatus("未接続", Color.DimGray);
    }

    private void OnDisconnectedUnexpectedly()
    {
        if (closing) return;
        connectButton.Enabled = true;
        disconnectButton.Enabled = false;
        updateButton.Enabled = true;
        repairButton.Enabled = true;
        SetStatus("切断されました。再接続できます。", Color.Firebrick);
    }

    private void SetBusy(bool busy)
    {
        updateButton.Enabled = !busy;
        connectButton.Enabled = !busy;
        repairButton.Enabled = !busy;
    }

    private void SetStatus(string text, Color color)
    {
        statusLabel.Text = text;
        statusLabel.ForeColor = color;
    }

    private void LoadSettings()
    {
        try
        {
            if (!File.Exists(SettingsPath)) return;
            var settings = JsonSerializer.Deserialize<ClientSettings>(File.ReadAllText(SettingsPath));
            keyBox.Text = settings?.ConnectionKey ?? string.Empty;
        }
        catch { }
    }

    private void SaveSettings(string key)
    {
        File.WriteAllText(SettingsPath,
            JsonSerializer.Serialize(new ClientSettings { ConnectionKey = key }), new UTF8Encoding(true));
    }

    private static Process StartProcess(string executable, string arguments, bool redirect)
    {
        var process = new Process
        {
            StartInfo = new ProcessStartInfo(executable, arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = redirect,
                RedirectStandardError = redirect
            }
        };
        if (!process.Start()) throw new InvalidOperationException($"{executable}を起動できませんでした。");
        return process;
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs eventArgs)
    {
        closing = true;
        Disconnect();
    }

    private sealed class ClientSettings
    {
        public string ConnectionKey { get; set; } = string.Empty;
    }
}
