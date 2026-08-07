# Palworld Join（ローカル開発版）

参加者がPowerShellを操作せず、公式Unlim CLIの初回導入、次回以降の更新確認、接続キーによる接続、Palworld用ローカルポートの確認、切断を行うWindowsアプリです。

## 現在の扱い

- ローカル開発専用です。
- GitHub Releasesでは配布しません。
- 完全な未導入Windows PCと実際のPalworld接続で合格するまで正式版にしません。

## 設計上の原則

- Unlim CLIを改変しません。
- 公式APIの配布URL、サイズ、SHA-256を照合します。
- ポート番号を固定せず、CLI出力と接続前後のWindows待受ポート差分から候補を取得します。
- 8989を除外しません。
- 複数候補がある場合は利用者がログを見て選択できます。
- アプリ自身が開始したUnlimプロセスだけを停止します。
- 更新失敗時は旧バイナリを復元します。

Powered by Unlim: https://unlim.cc/

本アプリはPocketpair, Inc.およびUnlimの公式製品ではありません。
