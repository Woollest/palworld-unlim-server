using System.Text;
using System.Text.Json;

namespace PalworldJoin;

internal static class SettingsStore
{
    internal static AppSettings Load()
    {
        try
        {
            if (!File.Exists(AppPaths.Settings)) return new AppSettings();
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(AppPaths.Settings)) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    internal static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(AppPaths.DataDirectory);
        File.WriteAllText(AppPaths.Settings,
            JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }),
            new UTF8Encoding(true));
    }
}
