# PalOps Desktop

Tauri 2とWindows WebView2を使用する、PalOpsの軽量デスクトップシェルです。

## 利用者向け

PalOps EXEが通常のサーバー管理画面です。[最新のGitHub Release](https://github.com/Woollest/palworld-unlim-server/releases/latest)から`PalOps_*_x64-setup.exe`を取得してインストールし、以後はスタートメニューの「PalOps」から起動してください。

初回起動時に既存のPalworldServerフォルダーを選択します。選択内容はユーザーのローカル設定へ保存され、次回から自動的に使用されます。PalOpsが停止中なら`dashboard.ps1`を非表示で起動し、`http://127.0.0.1:8765/`だけを専用ウィンドウへ表示します。EXEを閉じてもPalworld、Unlim、バックグラウンド管理機能は停止しません。サーバーを終了するときはアプリ内の「安全停止」を使用します。

二重起動時は新しいプロセスを終了し、既存のPalOpsウィンドウを前面へ戻します。リリース版は起動時にGitHub Releaseを確認し、利用者の同意後に署名を検証して更新します。

WindowsのAuthenticodeコード署名は現在使用していないため、初回インストール時にSmartScreen警告が表示される場合があります。GitHub公式Release以外から入手したインストーラーは実行しないでください。これはアプリ内更新の改ざん検証用署名とは別の仕組みです。

## 開発者向け

通常のEXEビルド：

```powershell
cargo build --release --locked --manifest-path desktop/src-tauri/Cargo.toml
```

出力先：

```text
desktop/src-tauri/target/release/palops.exe
```

NSISインストーラーのビルド：

```powershell
Push-Location desktop
npx --yes @tauri-apps/cli@2.11.4 build --bundles nsis
Pop-Location
```

リリース管理と更新署名は[Desktop release](../docs/DESKTOP_RELEASE.md)を参照してください。
