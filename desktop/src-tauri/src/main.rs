#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{
    env,
    net::TcpStream,
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::{Duration, Instant},
};
use tauri::{WebviewUrl, WebviewWindowBuilder};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const PALOPS_URL: &str = "http://127.0.0.1:8765/";

fn is_project_dir(path: &Path) -> bool {
    path.join("scripts/dashboard.ps1").is_file()
        && path.join("scripts/run-hidden-pwsh.vbs").is_file()
}

fn find_project_dir() -> Option<PathBuf> {
    if let Some(path) = env::var_os("PALOPS_PROJECT_DIR")
        .map(PathBuf::from)
        .filter(|path| is_project_dir(path))
    {
        return Some(path);
    }
    let roots = [
        env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(Path::to_path_buf)),
        env::current_dir().ok(),
        Some(PathBuf::from(env!("CARGO_MANIFEST_DIR"))),
    ];
    roots.into_iter().flatten().find_map(|root| {
        root.ancestors()
            .find(|path| is_project_dir(path))
            .map(Path::to_path_buf)
    })
}

fn dashboard_ready() -> bool {
    TcpStream::connect_timeout(
        &"127.0.0.1:8765".parse().expect("valid address"),
        Duration::from_millis(400),
    )
    .is_ok()
}

fn ensure_dashboard(project_dir: &Path) -> Result<(), String> {
    if dashboard_ready() {
        return Ok(());
    }
    let runner = project_dir.join("scripts/run-hidden-pwsh.vbs");
    let dashboard = project_dir.join("scripts/dashboard.ps1");
    let mut command = Command::new("wscript.exe");
    command
        .current_dir(project_dir)
        .args(["//B", "//Nologo"])
        .arg(runner)
        .arg(dashboard)
        .arg("-NoBrowser");
    #[cfg(windows)]
    command.creation_flags(0x08000000);
    command
        .spawn()
        .map_err(|error| format!("PalOpsを起動できませんでした: {error}"))?;
    let deadline = Instant::now() + Duration::from_secs(20);
    while Instant::now() < deadline {
        if dashboard_ready() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(300));
    }
    Err(
        "PalOpsの起動確認がタイムアウトしました。logs/dashboard-error.logを確認してください。"
            .into(),
    )
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let project_dir = find_project_dir().ok_or("PalworldServerフォルダーを検出できませんでした。EXEをプロジェクト内へ配置するかPALOPS_PROJECT_DIRを設定してください。")?;
            ensure_dashboard(&project_dir)?;
            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(PALOPS_URL.parse()?))
                .title("PalOps — Palworld Server Manager")
                .inner_size(1180.0, 820.0)
                .min_inner_size(840.0, 620.0)
                .center()
                .on_navigation(|url| url.scheme() == "http" && url.host_str() == Some("127.0.0.1") && url.port_or_known_default() == Some(8765))
                .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("PalOps desktop failed");
}
