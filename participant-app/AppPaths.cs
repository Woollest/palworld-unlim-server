namespace PalworldJoin;

internal static class AppPaths
{
    internal static readonly string DataDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PalworldJoin");
    internal static readonly string Settings = Path.Combine(DataDirectory, "settings.json");
    internal static readonly string Log = Path.Combine(DataDirectory, "session.log");
    internal static readonly string UnlimDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Unlim");
    internal static readonly string UnlimExecutable = Path.Combine(UnlimDirectory, "unlim.exe");
}
