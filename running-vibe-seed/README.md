# Run Trace

バイブコーディング練習用の最小ランニングWebアプリです。

## 機能

- iPhone / スマホの位置情報を連続取得
- OpenStreetMap 上に走行ルートを描画
- 距離、経過時間、現在標高、GPS精度を表示
- 標高グラフと累積上昇量を表示
- GPSなしでUIを確認できるデモ走行

## 実行

GitHub Pages で公開すると HTTPS になるため、Safari から位置情報を利用できます。

Webアプリの制約として、iPhoneで画面ロックしたりSafariをバックグラウンドにすると位置情報の継続取得が止まることがあります。本格的なランニング記録用途ではネイティブアプリ化が適しています。

## 構成

- `site/index.html` — アプリ本体。HTML/CSS/JavaScriptを1ファイルにまとめています。
- `.github/workflows/pages.yml` — GitHub Pagesへの自動デプロイ。

バックエンド、DB、ログイン機能はありません。
