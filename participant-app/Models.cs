using System.Text.Json.Serialization;

namespace PalworldJoin;

internal sealed class AppSettings
{
    public bool SaveConnectionKey { get; set; }
    public string ConnectionKey { get; set; } = string.Empty;
    public bool DarkMode { get; set; }
    public DateTimeOffset? LastUpdateCheck { get; set; }
}

internal sealed class UnlimManifest
{
    [JsonPropertyName("version")]
    public string Version { get; set; } = string.Empty;

    [JsonPropertyName("downloads")]
    public Dictionary<string, string> Downloads { get; set; } = [];

    [JsonPropertyName("hashes")]
    public Dictionary<string, UnlimHash> Hashes { get; set; } = [];
}

internal sealed class UnlimHash
{
    [JsonPropertyName("sha256")]
    public string Sha256 { get; set; } = string.Empty;

    [JsonPropertyName("size")]
    public long Size { get; set; }
}

internal sealed record UpdateStatus(string? InstalledVersion, string LatestVersion, bool UpdateAvailable);

internal sealed class UnlimInUseException(IReadOnlyCollection<int> processIds)
    : IOException($"Unlimが起動中です（PID: {string.Join(", ", processIds)}）。")
{
    internal IReadOnlyCollection<int> ProcessIds { get; } = processIds;
}
