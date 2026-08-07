# Palworld Unlim Client

参加者向けのWindowsアプリです。Discordの接続キーを入力すると、Unlim CLIを使ってPalworldサーバーへ接続します。通常は配布ZIP内の `PalworldUnlimClient.exe` だけで利用できます。

## 使い方

1. `PalworldUnlimClient.exe`をダブルクリックします。
2. Discordに掲載された接続キーを貼り付けます。
3. `接続`を押します。
4. アプリに表示されたアドレスをPalworldの専用サーバー接続欄へ入力します。
5. 遊び終わったら`切断`を押します。

Unlimが未導入の場合は、画面の案内から公式版を導入できます。`Unlimを更新`を押すと、公式API `https://api.zpw.jp/unlimmap` から最新版の配布URL・サイズ・SHA-256を取得し、すべての検証に成功した場合だけUnlimを置き換えます。

Unlimが存在しない初回導入では、既存プロセスや残存環境の競合確認を行わず、そのまま公式版の取得と検証へ進みます。競合確認は、実際にUnlim本体が存在する更新時と接続開始時だけ行います。

GUI版または別のCLI版Unlimが起動している場合は、競合を検出して終了確認を表示します。管理者権限で動作しているUnlimを終了できない場合やファイル操作を拒否された場合は、タスクマネージャーでUnlimを終了するか、参加アプリを右クリックして `管理者として実行` してください。通常の接続では管理者権限は不要です。

インストールされていないはずなのにUnlimの残存エラーが出る場合は、`環境修復`を押してください。検出したプロセスのPID・実行場所と残存フォルダーを表示し、確認後にUnlim専用フォルダーだけを削除して公式版を再導入します。診断内容は `%LOCALAPPDATA%\PalworldUnlimClient\app-diagnostics.log` に保存されます。

署名なしの開発版では、Windows SmartScreenが警告を表示する場合があります。配布元を確認したうえで「詳細情報」から実行してください。

## ポートについて

- 通常のPalworld接続先は `127.0.0.1:8211` です。
- ローカルの8211番が使用中の場合、Unlimが別の空きポートを割り当てます。アプリはUnlimの出力から検出した接続先を表示します。
- Unlim CLIのヘルプに出る既定値 `8989` はUnlim内部のオプションであり、Palworldのゲーム接続先ではありません。

## 配布時の注意

このフォルダーにUnlim本体は同梱していません。Unlimは必ず公式配布元から取得します。

Powered by Unlim: https://unlim.cc/

このクライアントはPocketpair, Inc.およびUnlimの公式製品ではありません。

## 開発者向けビルド

`.NET 10 SDK`を導入したWindowsで、プロジェクトルートから次を実行します。

```powershell
dotnet publish .\participant-client\src\PalworldUnlimClient.csproj -c Release -r win-x64 --self-contained true -o .\dist\participant-client-exe
```
