# Palworld Unlim Client

参加者向けのWindowsアプリです。Discordの接続キーを入力すると、Unlim CLIを使ってPalworldサーバーへ接続します。通常は配布ZIP内の `PalworldUnlimClient.exe` だけで利用できます。

## 使い方

1. `PalworldUnlimClient.exe`をダブルクリックします。
2. Discordに掲載された接続キーを貼り付けます。
3. `接続`を押します。
4. アプリに表示されたアドレスをPalworldの専用サーバー接続欄へ入力します。
5. 遊び終わったら`切断`を押します。

Unlimが未導入の場合は、画面の案内から公式版を導入できます。`Unlimを更新`を押すと、公式API `https://api.zpw.jp/unlimmap` から最新版の配布URL・サイズ・SHA-256を取得し、すべての検証に成功した場合だけUnlimを置き換えます。

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
