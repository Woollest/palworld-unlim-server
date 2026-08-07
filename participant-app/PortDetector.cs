using System.Net.NetworkInformation;
using System.Text.RegularExpressions;

namespace PalworldJoin;

internal sealed class PortDetector
{
    private static readonly Regex AnsiPattern = new(
        @"\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1B\\))",
        RegexOptions.Compiled);
    private static readonly Regex[] AuthoritativePatterns =
    [
        new(@"(?<port>\d{2,5})/(?:tcp|udp)\s*(?:→|->)\s*(?:localhost|127\.0\.0\.1):(?<local>\d{2,5})", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new(@"Access\s+application\s+on\s+(?:localhost|127\.0\.0\.1):(?<port>\d{2,5})", RegexOptions.IgnoreCase | RegexOptions.Compiled)
    ];
    private static readonly Regex[] SupportingPatterns =
    [
        new(@"(?:localhost|127\.0\.0\.1)\s*[:=\-]>?\s*(?<port>\d{2,5})", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new(@"(?:local(?:\s+port)?|listen(?:ing|er)?|mapped|proxy)\D{0,24}(?<port>\d{2,5})", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new(@"(?<port>\d{2,5})\s*(?:/udp|udp)", RegexOptions.IgnoreCase | RegexOptions.Compiled)
    ];

    private readonly HashSet<int> baseline;
    private readonly Dictionary<int, int> candidates = [];
    private readonly HashSet<int> authoritativePorts = [];

    internal PortDetector() => baseline = CaptureListeners();

    internal IReadOnlyCollection<int> Candidates => candidates.Keys.OrderBy(port => port).ToArray();
    internal int? RecommendedPort => candidates.Count == 0
        ? null
        : candidates.OrderByDescending(pair => pair.Value).ThenByDescending(pair => pair.Key).First().Key;

    internal void ObserveOutput(string line)
    {
        var clean = StripAnsi(line);
        var foundAuthoritative = false;
        foreach (var pattern in AuthoritativePatterns)
        foreach (Match match in pattern.Matches(clean))
        {
            var value = match.Groups["local"].Success
                ? match.Groups["local"].Value
                : match.Groups["port"].Value;
            if (int.TryParse(value, out var port) && port is > 0 and <= 65535)
            {
                authoritativePorts.Add(port);
                foundAuthoritative = true;
            }
        }

        if (foundAuthoritative)
        {
            candidates.Clear();
            foreach (var port in authoritativePorts) AddCandidate(port, priority: 1000);
            return;
        }
        if (authoritativePorts.Count > 0) return;

        foreach (var pattern in SupportingPatterns)
        foreach (Match match in pattern.Matches(clean))
            if (int.TryParse(match.Groups["port"].Value, out var port) && port is > 0 and <= 65535)
                AddCandidate(port, priority: 100);
    }

    internal void ObserveNewListeners()
    {
        if (authoritativePorts.Count > 0) return;
        foreach (var port in CaptureListeners().Except(baseline)) AddCandidate(port, priority: 10);
    }

    internal static string StripAnsi(string value) => AnsiPattern.Replace(value, string.Empty);

    internal static void RunSelfTest()
    {
        var detector = new PortDetector();
        detector.ObserveOutput("\u001b[0m  8989/tcp → localhost:8989");
        detector.ObserveOutput("\u001b[36mAccess application on\u001b[0m 127.0.0.1:8989");
        detector.ObserveOutput("connected via TCP (host dialed us: 192.168.1.156:49159)");
        if (detector.RecommendedPort != 8989 || detector.Candidates.Count != 1 ||
            detector.Candidates.Single() != 8989)
            throw new InvalidOperationException("Authoritative Unlim port mapping self-test failed.");
        if (StripAnsi("\u001b[36mAccess\u001b[0m") != "Access")
            throw new InvalidOperationException("ANSI stripping self-test failed.");
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
