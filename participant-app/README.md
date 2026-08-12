# Palworld Join — 参加者向け正式版

Palworld Joinは、PowerShellを使わずにUnlim経由でPalworld Dedicated Serverへ参加するWindowsアプリです。

## インストール

1. [Palworld Join v1.0.1 Release](https://github.com/Woollest/palworld-unlim-server/releases/tag/participant-v1.0.1)から`Palworld-Join-Setup-1.0.1.exe`をダウンロードします。
2. セットアップを実行します。
3. 必要に応じてデスクトップショートカットを作成します。

コード署名を行っていないため、Windows SmartScreenが表示される場合があります。本リポジトリのReleaseから取得したことを確認し、`詳細情報`→`実行`を選択してください。

## 参加方法

1. Palworld Joinを起動します。
2. 管理者から共有された接続キーを入力します。
3. `接続する`を押します。
4. 表示された`127.0.0.1:ポート番号`を`接続先をコピー`でコピーします。
5. Steam版Palworldの専用サーバー接続欄へ貼り付けます。

参加中はPalworld Joinを終了しないでください。終了時は`切断`を押します。ポート番号は固定ではなく、Unlimから返された値をアプリが検出します。

## 主な機能

- 初回起動時のUnlim CLI導入
- 次回起動時のUnlim更新確認
- 公式配布ファイルのサイズ・SHA-256検証
- 接続キーの任意保存
- `127.0.0.1:ポート番号`の自動検出とコピー
- ライト／ダークテーマ
- スタートメニュー、デスクトップショートカット、アンインストール対応

アプリ自身が開始したUnlimだけを終了します。別のUnlimが稼働中の場合は更新を保留し、強制終了しません。

Powered by Unlim: https://unlim.cc/

本アプリはPocketpair, Inc.およびUnlimの公式製品ではありません。
