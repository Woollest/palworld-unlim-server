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

二重起動時は新しいプロセスを終了し、既存のPalOpsウィンドウを前面へ戻します。アプリアイコンも組み込み済みです。Windowsコード署名と署名付き自動更新は、証明書と更新署名鍵を用意した後に有効化します。
