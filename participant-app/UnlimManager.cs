using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PalworldJoin;

internal sealed class UnlimManager
{
    private const string ManifestUrl = "https://api.zpw.jp/unlimmap";

    internal bool IsInstalled => File.Exists(AppPaths.UnlimExecutable);

    internal async Task<UpdateStatus> CheckForUpdateAsync(CancellationToken cancellationToken = default)
    {
        var installed = IsInstalled ? await ReadVersionAsync(cancellationToken) : null;
        var manifest = await GetManifestAsync(cancellationToken);
        return new UpdateStatus(installed, manifest.Version,
            !string.Equals(installed, manifest.Version, StringComparison.OrdinalIgnoreCase));
    }

    internal async Task<string> InstallOrUpdateAsync(bool firstInstall,
        IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        if (firstInstall)
        {
            progress?.Report("Windows Defenderの初回設定を確認しています…");
            await EnsureDefenderExclusionAsync(cancellationToken);
        }

        progress?.Report("公式の最新版情報を確認しています…");
        var manifest = await GetManifestAsync(cancellationToken);
        var platform = RuntimeInformation.OSArchitecture == Architecture.Arm64
            ? "windows_arm64"
            : "windows_amd64";
        if (!manifest.Downloads.TryGetValue(platform, out var downloadUrl) ||
            !manifest.Hashes.TryGetValue(platform, out var expected) ||
            string.IsNullOrWhiteSpace(downloadUrl) || expected.Size <= 0 || expected.Sha256.Length != 64)
            throw new InvalidOperationException($"公式APIに{platform}の完全な配布情報がありません。");

        Directory.CreateDirectory(AppPaths.DataDirectory);
        Directory.CreateDirectory(AppPaths.UnlimDirectory);
        var staging = Path.Combine(AppPaths.DataDirectory, $"unlim-{manifest.Version}.download");
        var backup = Path.Combine(AppPaths.DataDirectory, "unlim.previous.exe");
        var cacheBust = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var separator = downloadUrl.Contains('?') ? '&' : '?';

        try
        {
            progress?.Report($"Unlim {manifest.Version}をダウンロードしています…");
            using var client = CreateHttpClient();
            using var response = await client.GetAsync($"{downloadUrl}{separator}cachebust={cacheBust}",
                HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            response.EnsureSuccessStatusCode();
            await using (var source = await response.Content.ReadAsStreamAsync(cancellationToken))
            await using (var target = new FileStream(staging, FileMode.Create, FileAccess.Write, FileShare.None))
                await source.CopyToAsync(target, cancellationToken);

            progress?.Report("ファイルサイズとSHA-256を検証しています…");
            if (new FileInfo(staging).Length != expected.Size)
                throw new InvalidOperationException("ダウンロードサイズが公式情報と一致しません。");
            await using var stream = File.OpenRead(staging);
            var actualHash = Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken));
            if (!string.Equals(actualHash, expected.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("SHA-256が公式情報と一致しません。");

            if (File.Exists(AppPaths.UnlimExecutable))
                File.Copy(AppPaths.UnlimExecutable, backup, overwrite: true);
            File.Move(staging, AppPaths.UnlimExecutable, overwrite: true);

            progress?.Report("Unlimを実行してバージョンを確認しています…");
            var installed = await ReadVersionAsync(cancellationToken);
            if (!string.Equals(installed, manifest.Version, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(
                    $"実行されたバージョンが一致しません（期待: {manifest.Version}, 実際: {installed}）。");
            return installed;
        }
        catch
        {
            if (File.Exists(backup)) File.Copy(backup, AppPaths.UnlimExecutable, overwrite: true);
            throw;
        }
        finally
        {
            if (File.Exists(staging)) File.Delete(staging);
        }
    }

    internal async Task<string> ReadVersionAsync(CancellationToken cancellationToken = default)
    {
        if (!IsInstalled) throw new FileNotFoundException("Unlimがインストールされていません。");
        var info = new ProcessStartInfo(AppPaths.UnlimExecutable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        info.ArgumentList.Add("--version");
        using var process = Process.Start(info) ?? throw new InvalidOperationException("Unlimを起動できません。");
        var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var error = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"Unlimの実行確認に失敗しました: {error.Trim()}");
        return output.Trim().Split('\n', StringSplitOptions.RemoveEmptyEntries).LastOrDefault()?.Trim()
               ?? throw new InvalidOperationException("Unlimからバージョンが返りませんでした。");
    }

    private static async Task<UnlimManifest> GetManifestAsync(CancellationToken cancellationToken)
    {
        using var client = CreateHttpClient();
        var cacheBust = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        await using var stream = await client.GetStreamAsync($"{ManifestUrl}?cachebust={cacheBust}", cancellationToken);
        return await JsonSerializer.DeserializeAsync<UnlimManifest>(stream, cancellationToken: cancellationToken)
               ?? throw new InvalidOperationException("公式APIの応答を読み取れませんでした。");
    }

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(45) };
        client.DefaultRequestHeaders.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue
            { NoCache = true, NoStore = true };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PalworldJoin/0.1.1");
        return client;
    }

    private static async Task EnsureDefenderExclusionAsync(CancellationToken cancellationToken)
    {
        var escaped = AppPaths.UnlimDirectory.Replace("'", "''");
        var script = "$ErrorActionPreference='Stop';" +
                     $"Add-MpPreference -ExclusionPath '{escaped}';" +
                     $"if (-not ((Get-MpPreference).ExclusionPath -contains '{escaped}')) {{ exit 2 }}";
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        var info = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden
        };
        info.ArgumentList.Add("-NoProfile");
        info.ArgumentList.Add("-NonInteractive");
        info.ArgumentList.Add("-EncodedCommand");
        info.ArgumentList.Add(encoded);
        try
        {
            using var process = Process.Start(info) ??
                                throw new InvalidOperationException("管理者用セットアップを開始できません。");
            await process.WaitForExitAsync(cancellationToken);
            if (process.ExitCode != 0)
                throw new InvalidOperationException($"Defender設定を確認できません（終了コード: {process.ExitCode}）。");
        }
        catch (Win32Exception exception) when (exception.NativeErrorCode == 1223)
        {
            throw new OperationCanceledException("管理者の確認がキャンセルされました。", exception);
        }
    }
}
