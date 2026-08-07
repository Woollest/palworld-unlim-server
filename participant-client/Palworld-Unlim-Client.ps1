[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$AppName = 'Palworld Unlim Client'
$AppDataDirectory = Join-Path $env:LOCALAPPDATA 'PalworldUnlimClient'
$SettingsPath = Join-Path $AppDataDirectory 'settings.json'
$LogPath = Join-Path $AppDataDirectory 'unlim-client.log'
$UnlimProcess = $null
$DetectedGamePort = 8211

New-Item -ItemType Directory -Path $AppDataDirectory -Force | Out-Null

function Find-UnlimExecutable {
    $Candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Unlim\unlim.exe'),
        (Join-Path $env:APPDATA 'unlim\bin\unlim.exe')
    )

    $Command = Get-Command unlim -ErrorAction SilentlyContinue
    if ($Command -and $Command.Source) {
        $Candidates += $Command.Source
    }

    return $Candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Load-SavedSettings {
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return
    }

    try {
        $Saved = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
        if ($Saved.connectionKey) {
            $KeyTextBox.Text = [string]$Saved.connectionKey
        }
    }
    catch {
        # A damaged optional settings file must not prevent joining the server.
    }
}

function Save-Settings {
    @{
        connectionKey = $KeyTextBox.Text.Trim()
    } | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Set-ConnectionState {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color
    )

    $StatusLabel.Text = $Text
    $StatusLabel.ForeColor = $Color
}

function Append-Log {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return
    }

    Add-Content -LiteralPath $LogPath -Value $Line -Encoding UTF8

    # Unlim normally preserves the host port. If it selects another local port,
    # prefer an explicitly displayed localhost mapping over any internal API port.
    $Matches = [regex]::Matches($Line, '(?:localhost|127\.0\.0\.1)[: ](?<port>\d{2,5})', 'IgnoreCase')
    foreach ($Match in $Matches) {
        $Port = [int]$Match.Groups['port'].Value
        if ($Port -ne 8989 -and $Port -ne 9800) {
            $script:DetectedGamePort = $Port
            $Form.BeginInvoke([Action]{
                $AddressTextBox.Text = "127.0.0.1:$script:DetectedGamePort"
            }) | Out-Null
        }
    }
}

function Refresh-UnlimVersion {
    $Executable = Find-UnlimExecutable
    if (-not $Executable) {
        $VersionLabel.Text = 'Unlim: 未インストール'
        return
    }

    try {
        $Version = (& $Executable --version 2>$null | Select-Object -Last 1).Trim()
        $VersionLabel.Text = "Unlim: $Version"
    }
    catch {
        $VersionLabel.Text = 'Unlim: バージョン確認失敗'
    }
}

function Install-OrUpdateUnlim {
    $UpdateButton.Enabled = $false
    $ConnectButton.Enabled = $false
    Set-ConnectionState 'Unlimを公式配布元から更新しています…' ([System.Drawing.Color]::DarkOrange)

    try {
        if ($script:UnlimProcess -and -not $script:UnlimProcess.HasExited) {
            throw '接続を切断してから更新してください。'
        }

        $InstallerPath = Join-Path $env:TEMP 'unlim-official-install.ps1'
        Invoke-WebRequest -Uri 'https://unlim.cc/install.ps1' -OutFile $InstallerPath -UseBasicParsing
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerPath
        if ($LASTEXITCODE -ne 0 -or -not (Find-UnlimExecutable)) {
            throw 'Unlimのインストールを確認できませんでした。'
        }

        Refresh-UnlimVersion
        Set-ConnectionState '更新が完了しました。接続できます。' ([System.Drawing.Color]::SeaGreen)
    }
    catch {
        Set-ConnectionState "更新失敗: $($_.Exception.Message)" ([System.Drawing.Color]::Firebrick)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $AppName, 'OK', 'Error') | Out-Null
    }
    finally {
        $UpdateButton.Enabled = $true
        $ConnectButton.Enabled = $true
    }
}

function Start-UnlimConnection {
    $Key = $KeyTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Key)) {
        [System.Windows.Forms.MessageBox]::Show('Discordに掲載された接続キーを入力してください。', $AppName, 'OK', 'Warning') | Out-Null
        return
    }

    if ($script:UnlimProcess -and -not $script:UnlimProcess.HasExited) {
        return
    }

    $Executable = Find-UnlimExecutable
    if (-not $Executable) {
        $Choice = [System.Windows.Forms.MessageBox]::Show('Unlimが見つかりません。今すぐインストールしますか？', $AppName, 'YesNo', 'Question')
        if ($Choice -eq 'Yes') {
            Install-OrUpdateUnlim
        }
        $Executable = Find-UnlimExecutable
        if (-not $Executable) {
            return
        }
    }

    Save-Settings
    $script:DetectedGamePort = 8211
    $AddressTextBox.Text = '127.0.0.1:8211'
    if (Test-Path -LiteralPath $LogPath) {
        Remove-Item -LiteralPath $LogPath -Force
    }

    try {
        $Info = [System.Diagnostics.ProcessStartInfo]::new()
        $Info.FileName = $Executable
        $Info.Arguments = "--connect `"$Key`" --no-tui --log"
        $Info.UseShellExecute = $false
        $Info.CreateNoWindow = $true
        $Info.RedirectStandardOutput = $true
        $Info.RedirectStandardError = $true
        $Info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $Info.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $Process = [System.Diagnostics.Process]::new()
        $Process.StartInfo = $Info
        $Process.EnableRaisingEvents = $true
        $Process.add_OutputDataReceived({ if ($_.Data) { Append-Log $_.Data } })
        $Process.add_ErrorDataReceived({ if ($_.Data) { Append-Log $_.Data } })
        $Process.add_Exited({
            $Form.BeginInvoke([Action]{
                Set-ConnectionState '切断されました。再接続できます。' ([System.Drawing.Color]::Firebrick)
                $ConnectButton.Enabled = $true
                $DisconnectButton.Enabled = $false
            }) | Out-Null
        })

        if (-not $Process.Start()) {
            throw 'Unlimを起動できませんでした。'
        }
        $Process.BeginOutputReadLine()
        $Process.BeginErrorReadLine()
        $script:UnlimProcess = $Process

        Set-ConnectionState '接続中です。Palworldを起動してください。' ([System.Drawing.Color]::SeaGreen)
        $ConnectButton.Enabled = $false
        $DisconnectButton.Enabled = $true
    }
    catch {
        Set-ConnectionState "接続失敗: $($_.Exception.Message)" ([System.Drawing.Color]::Firebrick)
    }
}

function Stop-UnlimConnection {
    if ($script:UnlimProcess -and -not $script:UnlimProcess.HasExited) {
        $script:UnlimProcess.Kill()
        $script:UnlimProcess.WaitForExit(3000) | Out-Null
    }
    $script:UnlimProcess = $null
    Set-ConnectionState '未接続' ([System.Drawing.Color]::DimGray)
    $ConnectButton.Enabled = $true
    $DisconnectButton.Enabled = $false
}

$Form = New-Object System.Windows.Forms.Form
$Form.Text = $AppName
$Form.Size = New-Object System.Drawing.Size(560, 430)
$Form.MinimumSize = New-Object System.Drawing.Size(560, 430)
$Form.StartPosition = 'CenterScreen'
$Form.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)
$Form.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 249)

$Title = New-Object System.Windows.Forms.Label
$Title.Text = 'Palworld サーバーに参加'
$Title.Font = New-Object System.Drawing.Font('Yu Gothic UI', 18, [System.Drawing.FontStyle]::Bold)
$Title.AutoSize = $true
$Title.Location = New-Object System.Drawing.Point(28, 24)
$Form.Controls.Add($Title)

$Description = New-Object System.Windows.Forms.Label
$Description.Text = 'Discordの接続キーを貼り付けて「接続」を押してください。'
$Description.AutoSize = $true
$Description.ForeColor = [System.Drawing.Color]::DimGray
$Description.Location = New-Object System.Drawing.Point(31, 66)
$Form.Controls.Add($Description)

$KeyLabel = New-Object System.Windows.Forms.Label
$KeyLabel.Text = '接続キー'
$KeyLabel.AutoSize = $true
$KeyLabel.Location = New-Object System.Drawing.Point(31, 104)
$Form.Controls.Add($KeyLabel)

$KeyTextBox = New-Object System.Windows.Forms.TextBox
$KeyTextBox.Location = New-Object System.Drawing.Point(34, 128)
$KeyTextBox.Size = New-Object System.Drawing.Size(480, 30)
$KeyTextBox.Anchor = 'Top,Left,Right'
$Form.Controls.Add($KeyTextBox)

$ConnectButton = New-Object System.Windows.Forms.Button
$ConnectButton.Text = '接続'
$ConnectButton.Location = New-Object System.Drawing.Point(34, 174)
$ConnectButton.Size = New-Object System.Drawing.Size(150, 42)
$ConnectButton.BackColor = [System.Drawing.Color]::FromArgb(36, 104, 214)
$ConnectButton.ForeColor = [System.Drawing.Color]::White
$ConnectButton.FlatStyle = 'Flat'
$ConnectButton.Add_Click({ Start-UnlimConnection })
$Form.Controls.Add($ConnectButton)

$DisconnectButton = New-Object System.Windows.Forms.Button
$DisconnectButton.Text = '切断'
$DisconnectButton.Location = New-Object System.Drawing.Point(194, 174)
$DisconnectButton.Size = New-Object System.Drawing.Size(110, 42)
$DisconnectButton.Enabled = $false
$DisconnectButton.Add_Click({ Stop-UnlimConnection })
$Form.Controls.Add($DisconnectButton)

$UpdateButton = New-Object System.Windows.Forms.Button
$UpdateButton.Text = 'Unlimを更新'
$UpdateButton.Location = New-Object System.Drawing.Point(314, 174)
$UpdateButton.Size = New-Object System.Drawing.Size(150, 42)
$UpdateButton.Add_Click({ Install-OrUpdateUnlim })
$Form.Controls.Add($UpdateButton)

$StatusHeading = New-Object System.Windows.Forms.Label
$StatusHeading.Text = '状態'
$StatusHeading.AutoSize = $true
$StatusHeading.Location = New-Object System.Drawing.Point(31, 244)
$Form.Controls.Add($StatusHeading)

$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Text = '未接続'
$StatusLabel.AutoSize = $true
$StatusLabel.Location = New-Object System.Drawing.Point(94, 244)
$StatusLabel.ForeColor = [System.Drawing.Color]::DimGray
$Form.Controls.Add($StatusLabel)

$AddressLabel = New-Object System.Windows.Forms.Label
$AddressLabel.Text = 'Palworldの接続先'
$AddressLabel.AutoSize = $true
$AddressLabel.Location = New-Object System.Drawing.Point(31, 283)
$Form.Controls.Add($AddressLabel)

$AddressTextBox = New-Object System.Windows.Forms.TextBox
$AddressTextBox.Text = '127.0.0.1:8211'
$AddressTextBox.ReadOnly = $true
$AddressTextBox.Location = New-Object System.Drawing.Point(34, 309)
$AddressTextBox.Size = New-Object System.Drawing.Size(330, 30)
$Form.Controls.Add($AddressTextBox)

$CopyButton = New-Object System.Windows.Forms.Button
$CopyButton.Text = 'コピー'
$CopyButton.Location = New-Object System.Drawing.Point(374, 307)
$CopyButton.Size = New-Object System.Drawing.Size(90, 34)
$CopyButton.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($AddressTextBox.Text) })
$Form.Controls.Add($CopyButton)

$VersionLabel = New-Object System.Windows.Forms.Label
$VersionLabel.Text = 'Unlim: 確認中'
$VersionLabel.AutoSize = $true
$VersionLabel.ForeColor = [System.Drawing.Color]::DimGray
$VersionLabel.Location = New-Object System.Drawing.Point(31, 361)
$Form.Controls.Add($VersionLabel)

$PortNote = New-Object System.Windows.Forms.Label
$PortNote.Text = '※ 8989はUnlim内部の既定ポートで、Palworldの接続先ではありません。'
$PortNote.AutoSize = $true
$PortNote.ForeColor = [System.Drawing.Color]::DimGray
$PortNote.Location = New-Object System.Drawing.Point(190, 361)
$Form.Controls.Add($PortNote)

$Form.Add_Shown({
    Load-SavedSettings
    Refresh-UnlimVersion
})
$Form.Add_FormClosing({ Stop-UnlimConnection })

[void]$Form.ShowDialog()
