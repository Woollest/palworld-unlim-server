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
        ClientSize = new Size(700, 740);
        MinimumSize = new Size(700, 740);
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Yu Gothic UI", 10F);
        BackColor = Color.FromArgb(241, 244, 248);

        var header = new Panel
        {
            Dock = DockStyle.Top,
            Height = 92,
            BackColor = Color.FromArgb(24, 72, 132)
        };
        var title = Label("Palworld Join", 24, 16, 21F, FontStyle.Bold);
        title.ForeColor = Color.White;
        var subtitle = Label("接続キーを入力するだけでPalworldサーバーへ参加できます", 27, 57, 10F);
        subtitle.ForeColor = Color.FromArgb(220, 231, 246);
        header.Controls.AddRange([title, subtitle]);
        Controls.Add(header);

        var statusCard = Card(20, 112, 660, 72);
        var statusTitle = Label("UNLIM", 18, 10, 8.5F, FontStyle.Bold);
        statusTitle.ForeColor = Color.FromArgb(92, 105, 122);
        unlimStatus.SetBounds(18, 35, 450, 26);
        unlimStatus.Text = "確認中…";
        ConfigureButton(installButton, "更新を確認", 505, 15, 130);
        installButton.Click += async (_, _) => await InstallOrUpdateFromButtonAsync();
        statusCard.Controls.AddRange([statusTitle, unlimStatus, installButton]);
        Controls.Add(statusCard);

        var joinCard = Card(20, 201, 660, 210);
        var joinTitle = Label("サーバーへ接続", 18, 14, 13F, FontStyle.Bold);
        var keyLabel = Label("接続キー", 18, 52, 9F, FontStyle.Bold);
        keyLabel.ForeColor = Color.FromArgb(70, 82, 98);
        keyBox.SetBounds(18, 78, 624, 32);
        keyBox.Text = settings.SaveConnectionKey ? settings.ConnectionKey : string.Empty;
        keyBox.BorderStyle = BorderStyle.FixedSingle;
        saveKey.Text = "接続キーをこのPCに保存する";
        saveKey.Checked = settings.SaveConnectionKey;
        saveKey.AutoSize = true;
        saveKey.SetBounds(18, 119, 260, 28);

        ConfigureButton(connectButton, "接続する", 18, 157, 160, Color.FromArgb(36, 104, 214), Color.White);
        ConfigureButton(disconnectButton, "切断", 188, 157, 110);
        disconnectButton.Enabled = false;
        connectButton.Click += (_, _) => Connect();
        disconnectButton.Click += (_, _) => Disconnect();
        connectionStatus.SetBounds(320, 166, 320, 26);
        connectionStatus.Text = "未接続";
        connectionStatus.ForeColor = Color.DimGray;
        joinCard.Controls.AddRange([joinTitle, keyLabel, keyBox, saveKey, connectButton, disconnectButton, connectionStatus]);
        Controls.Add(joinCard);

        var addressCard = Card(20, 428, 660, 96);
        var addressTitle = Label("PALWORLDの接続先", 18, 11, 8.5F, FontStyle.Bold);
        addressTitle.ForeColor = Color.FromArgb(92, 105, 122);
        portBox.SetBounds(18, 43, 445, 32);
        portBox.DropDownStyle = ComboBoxStyle.DropDown;
        portBox.Text = "ポートを検出中";
        ConfigureButton(copyButton, "接続先をコピー", 475, 39, 160);
        copyButton.Enabled = false;
        copyButton.Click += (_, _) => CopyAddress();
        addressCard.Controls.AddRange([addressTitle, portBox, copyButton]);
        Controls.Add(addressCard);

        var detail = Label("詳細ログ", 24, 548, 10F, FontStyle.Bold);
        Controls.Add(detail);
        logBox.SetBounds(20, 577, 660, 125);
        logBox.Multiline = true;
        logBox.ReadOnly = true;
        logBox.ScrollBars = ScrollBars.Vertical;
        logBox.BackColor = Color.White;
        logBox.BorderStyle = BorderStyle.FixedSingle;
        logBox.Font = new Font("Consolas", 9F);
        Controls.Add(logBox);

        var attribution = Label("Powered by Unlim  •  非公式参加ツール  •  PREVIEW", 400, 712, 8.5F);
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

    private static Panel Card(int x, int y, int width, int height) => new()
    {
        Location = new Point(x, y),
        Size = new Size(width, height),
        BackColor = Color.White,
        BorderStyle = BorderStyle.FixedSingle
    };

    private static void ConfigureButton(Button button, string text, int x, int y, int width,
        Color? backColor = null, Color? foreColor = null)
    {
        button.Text = text;
        button.SetBounds(x, y, width, 42);
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.Cursor = Cursors.Hand;
        button.BackColor = backColor ?? Color.FromArgb(229, 234, 241);
        button.ForeColor = foreColor ?? Color.FromArgb(35, 45, 60);
        if (backColor.HasValue) button.BackColor = backColor.Value;
        if (foreColor.HasValue) button.ForeColor = foreColor.Value;
    }
}
