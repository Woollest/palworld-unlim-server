using System.Net.NetworkInformation;
using System.Text.RegularExpressions;

namespace PalworldJoin;

internal sealed class PortDetector
{
    private static readonly Regex[] Patterns =
    [
        new(@"(?:localhost|127\.0\.0\.1)\s*[:=\-]>?\s*(?<port>\d{2,5})", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new(@"(?:local(?:\s+port)?|listen(?:ing|er)?|mapped|proxy)\D{0,24}(?<port>\d{2,5})", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new(@"(?<port>\d{2,5})\s*(?:/udp|udp)", RegexOptions.IgnoreCase | RegexOptions.Compiled)
    ];

    private readonly HashSet<int> baseline;
    private readonly Dictionary<int, int> candidates = [];

    internal PortDetector() => baseline = CaptureListeners();

    internal IReadOnlyCollection<int> Candidates => candidates.Keys.OrderBy(port => port).ToArray();
    internal int? RecommendedPort => candidates.Count == 0
        ? null
        : candidates.OrderByDescending(pair => pair.Value).ThenByDescending(pair => pair.Key).First().Key;

    internal void ObserveOutput(string line)
    {
        foreach (var pattern in Patterns)
        foreach (Match match in pattern.Matches(line))
            if (int.TryParse(match.Groups["port"].Value, out var port) && port is > 0 and <= 65535)
                AddCandidate(port, priority: 100);
    }

    internal void ObserveNewListeners()
    {
        foreach (var port in CaptureListeners().Except(baseline)) AddCandidate(port, priority: 10);
    }

    private void AddCandidate(int port, int priority)
    {
        if (!candidates.TryGetValue(port, out var current) || priority > current)
            candidates[port] = priority;
    }

    private static HashSet<int> CaptureListeners()
    {
        var properties = IPGlobalProperties.GetIPGlobalProperties();
        return properties.GetActiveUdpListeners().Select(endpoint => endpoint.Port)
            .Concat(properties.GetActiveTcpListeners().Select(endpoint => endpoint.Port))
            .Where(port => port is > 0 and <= 65535)
            .ToHashSet();
    }
}
