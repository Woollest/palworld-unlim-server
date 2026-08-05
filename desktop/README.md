# PalOps Desktop

Tauri 2とWindows WebView2を使用する、PalOpsの軽量デスクトップシェルです。

初回起動時に既存のPalworldServerフォルダーを選択します。選択内容はユーザーのローカル設定へ保存され、次回から自動的に使用されます。PalOpsが停止中なら`dashboard.ps1`を非表示で起動し、`http://127.0.0.1:8765/`だけを専用ウィンドウへ表示します。EXEを閉じてもPalworld、Unlim、PalOpsは停止しません。

```powershell
cargo build --release --locked --manifest-path desktop/src-tauri/Cargo.toml
```

出力先：

```text
desktop/src-tauri/target/release/palops.exe
```

正式なNSISインストーラーは次のコマンドで作成します。現在のユーザー向けにインストールされ、スタートメニューから起動できます。

```powershell
Push-Location desktop
npx --yes @tauri-apps/cli@2.11.4 build --bundles nsis
Pop-Location
```

二重起動時は新しいプロセスを終了し、既存のPalOpsウィンドウを前面へ戻します。アプリアイコンも組み込み済みです。リリース版は起動時にGitHub Releaseを確認し、利用者の同意後に署名を検証して更新します。リリース管理は[Desktop release](../docs/DESKTOP_RELEASE.md)を参照してください。

WindowsのAuthenticodeコード署名は現在使用していないため、初回インストール時にSmartScreen警告が表示される場合があります。これはアプリ内更新の改ざん検証用署名とは別の仕組みです。
