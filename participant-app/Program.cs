namespace PalworldJoin;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(true, "Local\\PalworldJoin", out var firstInstance);
        if (!firstInstance)
        {
            MessageBox.Show("参加アプリはすでに起動しています。", "Palworld Join",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm(Environment.GetCommandLineArgs().Contains("--smoke-test")));
    }
}
