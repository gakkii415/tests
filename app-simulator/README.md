# アプリ画面確認

GitHub上のExpoアプリを選び、MacのiPhone SimulatorまたはAndroid Emulatorで確認するためのローカルツールです。

## 使い方

1. `アプリ画面確認.app` を開く
2. GitHubから取得したアプリ一覧から確認したいアプリを選ぶ
3. 「iPhoneで開く」または「Androidで開く」を選ぶ
4. GitHubの最新版取得、必要な依存関係の更新、Simulator / Emulatorの準備、Expo起動まで自動で行う

ターミナル操作、GitHub DesktopでのPull、ローカルコードの手動差し替えは通常不要です。

## 現在の方針

- コードの正本はGitHub
- Mac側は固定ランチャーを起点にし、本体はGitHubから自動取得
- GitHubに接続できない場合は、利用可能な範囲で前回のキャッシュを使う
- 最近使ったアプリと端末を優先して表示する
- 1リポジトリに複数のExpoアプリがあっても個別に検出する
- `package.json` / `package-lock.json` が変わった場合だけ依存関係を更新する
- AndroidはEmulatorの起動完了を確認してからExpoへ接続する
- 長い処理では通知を出し、無反応に見える時間を減らす

## UI / UXで参考にしている考え方

### Apple Human Interface Guidelines

https://developer.apple.com/design/human-interface-guidelines/progress-indicators

処理中なのか停止しているのか分からない状態を避け、時間のかかる処理では現在の状態を明確に伝える考え方を採用しています。

https://developer.apple.com/design/human-interface-guidelines/feedback

成功・失敗・現在の状態を、必要な強さのフィードバックで知らせる考え方を採用しています。

### Raycast

https://www.raycast.com/blog/a-fresh-look-and-feel

「fast, simple, delightful」のうち、特に **fast / simple** を参考にしています。設定項目を増やすより、アプリ選択から起動までの手数を減らすことを優先します。

### Expo Orbit

https://docs.expo.dev/build/orbit/

Simulator / Emulatorの管理やアプリ起動をワンクリックに近づける考え方を参考にしています。ただし、このツールはGitHub上の自分のExpoアプリを直接見つけて最新版を準備することに特化します。

## あえて追加していないもの

現時点では、次の機能は複雑さに対して効果が小さいため追加していません。

- 大きな設定画面
- お気に入り管理
- Simulator / Emulatorの細かな機種選択
- 独自のプロジェクト登録作業

アプリ数や利用方法が増え、本当に必要になった時点で追加します。

## 自動更新

`launcher.applescript` はGitHub上の `main.applescript` を取得して実行します。通常の機能改善は `main.applescript` の更新だけでMac側へ反映されます。

## 必要な環境

- macOS
- Xcode + iOS Simulator（iPhone確認時）
- Android Studio + Android Emulator（Android確認時）
- Node.js / npm
- GitHub Personal Access Token（Contents: Read-only）

## エラー時

起動処理のログは `/tmp/app-screen-check.log` に保存されます。通常はユーザーが直接読む必要はなく、起動失敗時にアプリ画面確認が直近の内容を表示します。
