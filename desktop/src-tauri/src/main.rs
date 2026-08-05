#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{
    env, fs,
    net::TcpStream,
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::{Duration, Instant},
};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
#[cfg(not(debug_assertions))]
use tauri_plugin_updater::UpdaterExt;

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const PALOPS_URL: &str = "http://127.0.0.1:8765/?desktop=1";

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
    if let Some(path) = stored_project_dir().filter(|path| is_project_dir(path)) {
        return Some(path);
    }
    let roots = [
        env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(Path::to_path_buf)),
        env::current_dir().ok(),
        env::var_os("USERPROFILE").map(|home| PathBuf::from(home).join("PalworldServer")),
        env::var_os("USERPROFILE")
            .map(|home| PathBuf::from(home).join("Documents").join("PalworldServer")),
    ];
    roots.into_iter().flatten().find_map(|root| {
        root.ancestors()
            .find(|path| is_project_dir(path))
            .map(Path::to_path_buf)
    })
}

fn project_config_file() -> Option<PathBuf> {
    dirs::data_local_dir().map(|path| path.join("PalOps").join("project-path.txt"))
}

fn stored_project_dir() -> Option<PathBuf> {
    let value = fs::read_to_string(project_config_file()?).ok()?;
    let path = PathBuf::from(value.trim());
    (!value.trim().is_empty()).then_some(path)
}

fn remember_project_dir(path: &Path) {
    let Some(file) = project_config_file() else {
        return;
    };
    if let Some(parent) = file.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::write(file, path.to_string_lossy().as_bytes());
}

fn choose_project_dir() -> Option<PathBuf> {
    let path = rfd::FileDialog::new()
        .set_title("PalworldServerフォルダーを選択")
        .pick_folder()?;
    if is_project_dir(&path) {
        remember_project_dir(&path);
        return Some(path);
    }
    rfd::MessageDialog::new()
        .set_title("PalOps")
        .set_description(
            "選択したフォルダーに必要な管理ファイルがありません。PalworldServerフォルダーを選択してください。",
        )
        .set_level(rfd::MessageLevel::Error)
        .show();
    None
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

#[cfg(not(debug_assertions))]
fn check_for_updates(app: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        let result = async {
            let Some(update) = app.updater()?.check().await? else {
                return Ok::<(), tauri_plugin_updater::Error>(());
            };
            let accepted = rfd::MessageDialog::new()
                .set_title("PalOpsアップデート")
                .set_description(format!(
                    "PalOps {} を利用できます。今すぐ更新しますか？",
                    update.version
                ))
                .set_buttons(rfd::MessageButtons::YesNo)
                .show();
            if accepted == rfd::MessageDialogResult::Yes {
                update.download_and_install(|_, _| {}, || {}).await?;
            }
            Ok(())
        }
        .await;
        if let Err(error) = result {
            rfd::MessageDialog::new()
                .set_title("PalOpsアップデート")
                .set_description(format!("更新を確認または適用できませんでした。\n{error}"))
                .set_level(rfd::MessageLevel::Error)
                .show();
        }
    });
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let project_dir = find_project_dir()
                .or_else(choose_project_dir)
                .ok_or("PalworldServerフォルダーが選択されなかったため、PalOpsを終了します。")?;
            ensure_dashboard(&project_dir)?;
            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(PALOPS_URL.parse()?))
                .title("PalOps — Palworld Server Manager")
                .inner_size(1180.0, 820.0)
                .min_inner_size(840.0, 620.0)
                .center()
                .on_navigation(|url| {
                    url.scheme() == "http"
                        && url.host_str() == Some("127.0.0.1")
                        && url.port_or_known_default() == Some(8765)
                })
                .build()?;
            #[cfg(not(debug_assertions))]
            check_for_updates(app.handle().clone());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("PalOps desktop failed");
}
