# PalOps Desktop

Tauri 2とWindows WebView2を使用する、PalOpsの軽量デスクトップシェルです。

現段階のEXEは既存のPalworldServerフォルダー内で使用します。PalOpsが停止中なら`dashboard.ps1`を非表示で起動し、`http://127.0.0.1:8765/`だけを専用ウィンドウへ表示します。EXEを閉じてもPalworld、Unlim、PalOpsは停止しません。

```powershell
cargo build --release --locked --manifest-path desktop/src-tauri/Cargo.toml
```

出力先：

```text
desktop/src-tauri/target/release/palops.exe
```

アプリアイコンは組み込み済みです。今後の段階で、単一起動、署名、インストーラー、更新機能を追加します。
