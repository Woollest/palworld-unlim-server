using System.Text;
using System.Text.RegularExpressions;

namespace PalworldJoin;

internal sealed class MainForm : Form
{
    private static readonly Regex KeyPattern = new(@"^[A-Za-z0-9_-]{8,200}$", RegexOptions.Compiled);
    private readonly UnlimManager manager = new();
    private readonly UnlimSession session = new();
    private readonly AppSettings settings = SettingsStore.Load();
    private readonly Label unlimStatus = new();
    private readonly Label connectionStatus = new();
    private readonly TextBox keyBox = new();
    private readonly CheckBox saveKey = new();
    private readonly ComboBox portBox = new();
    private readonly TextBox logBox = new();
    private readonly Button installButton = new();
    private readonly Button connectButton = new();
    private readonly Button disconnectButton = new();
    private readonly Button copyButton = new();
    private readonly System.Windows.Forms.Timer listenerTimer = new() { Interval = 1000 };
    private PortDetector? portDetector;
    private bool closing;

    internal MainForm(bool suppressStartupActions = false)
    {
        Directory.CreateDirectory(AppPaths.DataDirectory);
        Text = "Palworld Join";
        ClientSize = new Size(700, 625);
        MinimumSize = new Size(700, 625);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Yu Gothic UI", 10F);
        BackColor = Color.FromArgb(247, 248, 250);

        var title = Label("Palworldサーバーに参加", 28, 22, 20F, FontStyle.Bold);
        var subtitle = Label("Unlim CLIの導入・更新・接続をこの画面で行います。", 31, 68, 10F);
        subtitle.ForeColor = Color.DimGray;
        Controls.AddRange([title, subtitle]);

        Controls.Add(Label("Unlim", 31, 111, 10F, FontStyle.Bold));
        unlimStatus.SetBounds(98, 111, 410, 26);
        unlimStatus.Text = "確認中…";
        Controls.Add(unlimStatus);
        ConfigureButton(installButton, "導入・更新", 535, 101, 130);
        installButton.Click += async (_, _) => await InstallOrUpdateFromButtonAsync();
        Controls.Add(installButton);

        Controls.Add(Label("接続キー", 31, 164, 10F, FontStyle.Bold));
        keyBox.SetBounds(34, 191, 631, 31);
        keyBox.Text = settings.SaveConnectionKey ? settings.ConnectionKey : string.Empty;
        Controls.Add(keyBox);
        saveKey.Text = "接続キーをこのPCに保存する";
        saveKey.Checked = settings.SaveConnectionKey;
        saveKey.AutoSize = true;
        saveKey.SetBounds(34, 230, 260, 28);
        Controls.Add(saveKey);

        ConfigureButton(connectButton, "接続", 34, 275, 160, Color.FromArgb(36, 104, 214), Color.White);
        ConfigureButton(disconnectButton, "切断", 204, 275, 120);
        disconnectButton.Enabled = false;
        connectButton.Click += (_, _) => Connect();
        disconnectButton.Click += (_, _) => Disconnect();
        Controls.AddRange([connectButton, disconnectButton]);

        connectionStatus.SetBounds(346, 285, 319, 26);
        connectionStatus.Text = "未接続";
        connectionStatus.ForeColor = Color.DimGray;
        Controls.Add(connectionStatus);

        Controls.Add(Label("Palworldの接続先", 31, 344, 10F, FontStyle.Bold));
        portBox.SetBounds(34, 372, 470, 32);
        portBox.DropDownStyle = ComboBoxStyle.DropDown;
        portBox.Text = "ポートを検出中";
        Controls.Add(portBox);
        ConfigureButton(copyButton, "接続先をコピー", 515, 370, 150);
        copyButton.Enabled = false;
        copyButton.Click += (_, _) => CopyAddress();
        Controls.Add(copyButton);

        var detail = Label("詳細ログ", 31, 430, 10F, FontStyle.Bold);
        Controls.Add(detail);
        logBox.SetBounds(34, 458, 631, 125);
        logBox.Multiline = true;
        logBox.ReadOnly = true;
        logBox.ScrollBars = ScrollBars.Vertical;
        logBox.BackColor = Color.White;
        logBox.Font = new Font("Consolas", 9F);
        Controls.Add(logBox);

        var attribution = Label("Powered by Unlim — 非公式参加ツール", 454, 593, 8.5F);
        attribution.ForeColor = Color.DimGray;
        Controls.Add(attribution);

        listenerTimer.Tick += (_, _) => RefreshDetectedPorts();
        session.OutputReceived += OnSessionOutput;
        session.Exited += () => BeginInvoke(() => OnSessionExited());
        Shown += async (_, _) =>
        {
            if (suppressStartupActions)
            {
                unlimStatus.Text = "スモークテスト";
                return;
            }
            await InitializeAsync();
        };
        FormClosing += (_, _) =>
        {
            closing = true;
            SaveSettings();
            listenerTimer.Stop();
            session.Dispose();
        };
    }

    private async Task InitializeAsync()
    {
        if (!manager.IsInstalled)
        {
            unlimStatus.Text = "未導入";
            unlimStatus.ForeColor = Color.DarkOrange;
            var answer = MessageBox.Show(
                "Unlim CLIが導入されていません。初回セットアップを開始しますか？\n\n管理者の確認画面が1回表示されます。",
                Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer == DialogResult.Yes) await InstallOrUpdateAsync(firstInstall: true);
            return;
        }

        await CheckForUpdatesAsync();
    }

    private async Task CheckForUpdatesAsync()
    {
        SetBusy(true);
        unlimStatus.Text = "更新を確認中…";
        try
        {
            var status = await manager.CheckForUpdateAsync();
            settings.LastUpdateCheck = DateTimeOffset.Now;
            SettingsStore.Save(settings);
            if (!status.UpdateAvailable)
            {
                unlimStatus.Text = $"導入済み {status.InstalledVersion}（最新版）";
                unlimStatus.ForeColor = Color.SeaGreen;
                return;
            }

            unlimStatus.Text = $"更新あり {status.InstalledVersion} → {status.LatestVersion}";
            unlimStatus.ForeColor = Color.DarkOrange;
            if (MessageBox.Show(
                    $"Unlim {status.LatestVersion}を利用できます。接続前に更新しますか？",
                    "Unlim更新", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                await InstallOrUpdateAsync(firstInstall: false);
        }
        catch (Exception exception)
        {
            unlimStatus.Text = "更新確認失敗（導入済み版は利用可能）";
            unlimStatus.ForeColor = Color.DarkOrange;
            AppendLog($"更新確認エラー: {exception.Message}");
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task InstallOrUpdateFromButtonAsync()
    {
        if (!manager.IsInstalled)
        {
            await InstallOrUpdateAsync(firstInstall: true);
            return;
        }

        SetBusy(true);
        unlimStatus.Text = "更新を確認中…";
        try
        {
            var status = await manager.CheckForUpdateAsync();
            if (!status.UpdateAvailable)
            {
                unlimStatus.Text = $"導入済み {status.InstalledVersion}（最新版）";
                unlimStatus.ForeColor = Color.SeaGreen;
                AppendLog($"Unlim {status.InstalledVersion}は最新版です。更新処理は行いませんでした。");
                return;
            }
            await InstallOrUpdateAsync(firstInstall: false);
        }
        catch (Exception exception)
        {
            unlimStatus.Text = "更新確認失敗";
            unlimStatus.ForeColor = Color.Firebrick;
            AppendLog($"更新確認エラー: {exception}");
            MessageBox.Show(exception.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task InstallOrUpdateAsync(bool firstInstall)
    {
        SetBusy(true);
        var progress = new Progress<string>(message =>
        {
            unlimStatus.Text = message;
            AppendLog(message);
        });
        try
        {
            var version = await manager.InstallOrUpdateAsync(firstInstall, progress);
            unlimStatus.Text = $"導入済み {version}（最新版）";
            unlimStatus.ForeColor = Color.SeaGreen;
            AppendLog($"Unlim {version}の導入と実行確認が完了しました。 ");
        }
        catch (OperationCanceledException exception)
        {
            unlimStatus.Text = "セットアップ中止";
            unlimStatus.ForeColor = Color.DarkOrange;
            AppendLog(exception.Message);
        }
        catch (UnlimInUseException exception)
        {
            unlimStatus.Text = "Unlim使用中のため更新保留";
            unlimStatus.ForeColor = Color.DarkOrange;
            AppendLog($"更新保留: {exception.Message}");
            MessageBox.Show(
                $"{exception.Message}\n\n接続またはサーバー公開を終了してから更新してください。" +
                "このアプリから他のUnlimを強制終了することはありません。",
                "Unlim使用中", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        catch (Exception exception)
        {
            unlimStatus.Text = "導入・更新失敗";
            unlimStatus.ForeColor = Color.Firebrick;
            AppendLog($"導入・更新エラー: {exception}");
            MessageBox.Show($"Unlimを導入・更新できませんでした。\n\n{exception.Message}\n\n" +
                            $"ログ: {AppPaths.Log}", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void Connect()
    {
        if (!manager.IsInstalled)
        {
            MessageBox.Show("先にUnlimを導入してください。", Text,
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        var key = keyBox.Text.Trim();
        if (!KeyPattern.IsMatch(key))
        {
            MessageBox.Show("Discordに掲載された接続キーを入力してください。", Text,
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        SaveSettings();
        try
        {
            portBox.Items.Clear();
            portBox.Text = "ポートを検出中";
            copyButton.Enabled = false;
            portDetector = new PortDetector();
            session.Connect(key);
            listenerTimer.Start();
            connectButton.Enabled = false;
            disconnectButton.Enabled = true;
            installButton.Enabled = false;
            connectionStatus.Text = "Unlim接続中・ポート検出中…";
            connectionStatus.ForeColor = Color.DarkOrange;
            AppendLog("Unlim CLIを起動しました。割り当てポートを待っています。");
        }
        catch (Exception exception)
        {
            AppendLog($"接続開始エラー: {exception}");
            MessageBox.Show(exception.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnSessionOutput(string line)
    {
        try
        {
            var clean = PortDetector.StripAnsi(line);
            portDetector?.ObserveOutput(clean);
            BeginInvoke(() =>
            {
                AppendLog(clean);
                RefreshDetectedPorts();
            });
        }
        catch { }
    }

    private void RefreshDetectedPorts()
    {
        if (portDetector is null) return;
        try { portDetector.ObserveNewListeners(); } catch { }
        var ports = portDetector.Candidates;
        if (portDetector.HasAuthoritativePort)
        {
            portBox.Items.Clear();
            foreach (var port in ports) portBox.Items.Add(port.ToString());
            if (portDetector.RecommendedPort is int authoritativePort)
                portBox.Text = authoritativePort.ToString();
        }
        foreach (var port in ports)
            if (!portBox.Items.Contains(port.ToString())) portBox.Items.Add(port.ToString());
        if (ports.Count == 0) return;
        if (!portDetector.HasAuthoritativePort &&
            (portBox.Text == "ポートを検出中" || string.IsNullOrWhiteSpace(portBox.Text)) &&
            portDetector.RecommendedPort is int recommended)
            portBox.Text = recommended.ToString();
        copyButton.Enabled = true;
        connectionStatus.Text = ports.Count == 1
            ? "接続先を検出しました"
            : "複数候補を検出しました。ログと候補を確認してください";
        connectionStatus.ForeColor = ports.Count == 1 ? Color.SeaGreen : Color.DarkOrange;
    }

    private void CopyAddress()
    {
        if (!int.TryParse(portBox.Text.Trim(), out var port) || port is <= 0 or > 65535)
        {
            MessageBox.Show("有効なポートを選択または入力してください。", Text,
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        Clipboard.SetText($"127.0.0.1:{port}");
        connectionStatus.Text = $"127.0.0.1:{port} をコピーしました";
    }

    private void Disconnect()
    {
        listenerTimer.Stop();
        session.Disconnect();
        portDetector = null;
        connectButton.Enabled = true;
        disconnectButton.Enabled = false;
        installButton.Enabled = true;
        connectionStatus.Text = "未接続";
        connectionStatus.ForeColor = Color.DimGray;
        AppendLog("Unlim接続を終了しました。");
    }

    private void OnSessionExited()
    {
        if (closing) return;
        listenerTimer.Stop();
        connectButton.Enabled = true;
        disconnectButton.Enabled = false;
        installButton.Enabled = true;
        connectionStatus.Text = "Unlimが終了しました。詳細ログを確認してください";
        connectionStatus.ForeColor = Color.Firebrick;
    }

    private void SaveSettings()
    {
        settings.SaveConnectionKey = saveKey.Checked;
        settings.ConnectionKey = saveKey.Checked ? keyBox.Text.Trim() : string.Empty;
        SettingsStore.Save(settings);
    }

    private void AppendLog(string line)
    {
        var formatted = $"[{DateTimeOffset.Now:HH:mm:ss}] {line}";
        logBox.AppendText(formatted + Environment.NewLine);
        try
        {
            File.AppendAllText(AppPaths.Log, formatted + Environment.NewLine, Encoding.UTF8);
        }
        catch { }
    }

    private void SetBusy(bool busy)
    {
        installButton.Enabled = !busy && !session.IsRunning;
        connectButton.Enabled = !busy && !session.IsRunning;
    }

    private Label Label(string text, int x, int y, float size = 10F,
        FontStyle style = FontStyle.Regular) => new()
    {
        Text = text,
        AutoSize = true,
        Location = new Point(x, y),
        Font = new Font("Yu Gothic UI", size, style)
    };

    private static void ConfigureButton(Button button, string text, int x, int y, int width,
        Color? backColor = null, Color? foreColor = null)
    {
        button.Text = text;
        button.SetBounds(x, y, width, 42);
        button.FlatStyle = FlatStyle.Flat;
        if (backColor.HasValue) button.BackColor = backColor.Value;
        if (foreColor.HasValue) button.ForeColor = foreColor.Value;
    }
}
