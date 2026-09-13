# RuncatTouchBar

RunCat Neo をベースに、MacBook Pro の **Touch Bar Control Strip** に RunCat を常駐させる実験的な派生版です。

普段は純正 Control Strip の中に小さな Runner だけを表示し、タップすると Touch Bar 上に簡易 Activity Monitor を展開します。

## Current prototype

- RunCat の連番アニメーションを Control Strip に常駐表示
- RunCat Neo と同じ CPU 負荷連動のアニメーション速度
- RunCat Neo 側で選択した Runner / Custom Runner を Touch Bar にも反映
- Runner をタップすると system modal Touch Bar を展開
- CPU 使用率をライブ表示
- RAM 使用量 / 総容量 / 使用率をライブ表示
- バッテリー残量 / 充電状態をライブ表示
- CPU 使用率上位のユーザープロセスを横スクロール表示
- 各プロセスのアプリアイコン・CPU使用率を表示
- 通常終了 (`SIGTERM`) と強制終了 (`SIGKILL`) を Touch Bar から実行
- 展開中は約1秒ごとにメトリクス / プロセス / バッテリーを更新
- 純正 Control Strip の音量・明るさなどは残す設計

## Requirements

- Touch Bar 搭載 MacBook Pro
- macOS 26+
- Xcode 26.5+
- Swift 6.2

## Implementation notes

Control Strip への常駐は Apple の公開 API だけでは実現できないため、以下の private API を実行時に動的取得して使用しています。

- `DFRElementSetControlStripPresenceForIdentifier`
- `DFRSystemModalShowsCloseBoxWhenFrontMost`
- `+[NSTouchBarItem addSystemTrayItem:]`
- `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]`

private API が見つからない環境では Control Strip 機能を開始しないようにしています。

プロセス一覧取得と他プロセスへの `SIGTERM` / `SIGKILL` のため、この派生版の app target は App Sandbox を無効化しています。Bundle ID は upstream と衝突しないよう `dev.nisesimadao.RuncatTouchBar` に分離しています。

## Build & test

ローカルで Touch Bar 実機テストする場合は、リポジトリのルートでこれを実行します。

```sh
bash scripts/build-test-app.sh
```

このスクリプトは、既存のテスト版を終了してから Debug ビルド → ad-hoc 署名 → `dist/RuncatTouchBar.app` 作成 → 起動確認までまとめて行います。ZIP も `RuncatTouchBar-test.zip` として生成します。

手動でビルドする場合:

```sh
xcodebuild build \
  -project RunCatNeo.xcodeproj \
  -scheme RunCatNeo \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

GitHub Actions の `Build & Package` でも unsigned build → ad-hoc 署名 → ZIP artifact 作成を行います。

## Upstream

This project is derived from **RunCat Neo** by Kyome22 / RunCat Developers.

- Upstream: https://github.com/runcat-dev/RunCatNeo
- License: Apache License 2.0

RunCat Neo の元ライセンスおよび著作権表示はリポジトリ内に保持しています。

## Status

Touch Bar の Control Strip 常駐と展開モニターは実装済みです。GitHub の macOS runner には物理 Touch Bar がないため、Control Strip への実表示・タップ展開・プロセス終了操作の最終確認は Touch Bar 搭載実機で行います。
