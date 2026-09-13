# RuncatTouchBar

指のすぐそばで走る RunCat。

[![Latest release](https://img.shields.io/github/v/release/nisesimadao/RuncatTouchBar?label=download)](https://github.com/nisesimadao/RuncatTouchBar/releases/latest)
[![Build & Release](https://github.com/nisesimadao/RuncatTouchBar/actions/workflows/release.yml/badge.svg)](https://github.com/nisesimadao/RuncatTouchBar/actions/workflows/release.yml)
[![macOS](https://img.shields.io/badge/macOS-26%2B-blue)](#必要環境)

<p align="center">
  <a href="docs/assets/touchbar-overview.webp">
    <img src="docs/assets/touchbar-overview.webp" alt="Control Strip上で動作するRuncatTouchBar" width="1200" />
  </a>
</p>

RuncatTouchBar は **RunCat Neo** をベースにした実験的な macOS ユーティリティです。MacBook Pro の **Control Strip** に選択中の RunCat を常駐させつつ、Apple 純正の明るさ・音量などの操作はそのまま残します。

Runner をタップすると、Touch Bar 上にコンパクトなシステムモニターを展開します。

[English README](./README.md)

## 主な機能

- **Control Strip に RunCat** — 純正コントロールの横に Runner を追加
- **RunCat 本体と状態共有** — Runner / Custom Runner / CPU連動アニメーション速度を共有
- **システム情報** — CPU・メモリ・ストレージ・ネットワーク・バッテリーを表示
- **監視設定を共有** — Memory / Storage / Network / Battery のON/OFFを本体設定に追従
- **更新間隔を共有** — RunCat側の 3 / 5 / 10秒設定をTouch Barにも反映
- **高CPUプロセス一覧** — アプリアイコンとCPU使用率を横スクロール表示
- **プロセス終了** — 通常終了と強制終了をTouch Barから実行
- **Activity Monitor** — 必要なときはmacOSのActivity Monitorへ直接移動
- **純正Control Stripを維持** — Touch Bar全体を置き換えず、system tray itemとして追加

## Touch Barモニター

<p align="center">
  <a href="docs/assets/expanded-monitor.webp">
    <img src="docs/assets/expanded-monitor.webp" alt="展開したRuncatTouchBarシステムモニター" width="1200" />
  </a>
</p>

システム情報は可能な限り RunCat 本体と同じ監視ソースを利用します。プロセス行は毎回作り直さず更新し、スワイプ中はCPU順位の並べ替えを抑えてスクロールのカクつきを減らしています。

プロセス名とCPU使用率は別フィールドに分け、名前が長くても `%` 側が省略されないようにしています。

## ダウンロード / インストール

[Releases](https://github.com/nisesimadao/RuncatTouchBar/releases/latest) から `RuncatTouchBar.zip` をダウンロードし、展開した `RuncatTouchBar.app` を `/Applications` に移動します。

Releaseビルドは **ad-hoc署名のみで、Developer ID署名・Notarizeはしていません**。初回起動時にGatekeeperで止められた場合:

1. `RuncatTouchBar.app` を右クリックして **開く**
2. 確認画面でもう一度 **開く**

必要なら次でも解除できます。

```bash
xattr -dr com.apple.quarantine /Applications/RuncatTouchBar.app
```

詳しくは [FAQ](./docs/FAQ.md) を参照してください。

## 設定

RuncatTouchBar専用の設定画面をもう1つ作るのではなく、既存のRunCat Neo設定をそのまま共有する方針です。

<p align="center">
  <a href="docs/assets/settings.webp">
    <img src="docs/assets/settings.webp" alt="RuncatTouchBarと共有するRunCat Neo設定" width="760" />
  </a>
</p>

Runner選択、Custom Runner、アニメーション速度、表示するメトリクス、監視更新間隔をメニューバー側とTouch Bar側で共通化しています。

## 必要環境

- Touch Bar搭載 MacBook Pro
- macOS 26以降
- 現在の配布ビルドはApple Silicon向け

ソースからビルドする場合は、現在 Xcode 26.5+ / Swift 6.2 を想定しています。

## private API / セキュリティについて

AppleはControl Stripへ任意の項目を追加する公開APIを提供していないため、RuncatTouchBarは `DFRElementSetControlStripPresenceForIdentifier` などのprivate APIやsystem tray / modal Touch Bar selectorを実行時に取得して利用します。

また、ユーザープロセスの確認・終了を行うため、RuncatTouchBar targetでは App Sandbox を無効化しています。これはプロセスモニター機能のための意図的なトレードオフです。詳しくは [Security](./docs/SECURITY.md) / [Privacy](./docs/PRIVACY.md) を参照してください。

必要なprivate APIが存在しない環境では、Control Strip機能を開始しません。

## 技術メモ

- Swift / SwiftUI + AppKit
- `NSTouchBar` + 動的取得したprivate Touch Bar API
- RunCat本体と共有する `AppDependencies` / state stream
- CPU・メモリ・ストレージ・ネットワーク・バッテリーは `SystemInfoKit`
- 高CPUプロセス取得は `ps`
- プロセス行はin-place更新 + スクロール中の順位変更を抑制
- Bundle ID: `dev.nisesimadao.RuncatTouchBar`

## ソースからビルド

Touch Bar実機テスト用:

```bash
bash scripts/build-test-app.sh
```

Release相当を直接ビルドする場合:

```bash
xcodebuild \
  -project RunCatNeo.xcodeproj \
  -scheme RunCatNeo \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## Release / CI

`vX.Y.Z` タグをpushするとRelease Workflowが実行され、arm64ビルド → バージョン確認 → ad-hoc署名 → `RuncatTouchBar.zip` 作成 → Artifact保存 → GitHub Release公開まで自動で行います。`docs/RELEASE_NOTES_vX.Y.Z.md` がある場合はその本文を使い、無ければGitHubの自動生成Release Notesを使います。

通常の `main` pushは従来の **Build & Package** Workflowで開発用artifactを作成します。

## ドキュメント

- [Changelog](./docs/CHANGELOG.md)
- [FAQ](./docs/FAQ.md)
- [Privacy](./docs/PRIVACY.md)
- [Security](./docs/SECURITY.md)
- [スクリーンショット撮影チェックリスト](./docs/DEMO_ASSETS.md)
- [Releaseチェックリスト](./docs/RELEASE_CHECKLIST.md)
- [Release Notesテンプレート](./docs/RELEASE_NOTES_TEMPLATE.md)
- [Contributing](./CONTRIBUTING.md)
- [License](./LICENSE)

## Upstream

RuncatTouchBar は Kyome22 / RunCat Developers による **RunCat Neo** をベースにしています。

- Upstream: https://github.com/runcat-dev/RunCatNeo
- License: Apache License 2.0

元プロジェクトのライセンス・著作権表示はリポジトリ内に保持しています。

## 現在の状態

GitHub Actions上でコンパイル・パッケージ成功を確認しています。Touch Bar搭載実機でもControl Strip表示と展開表示を確認済みです。プロセス終了機能は実際のユーザープロセスを終了するため、使用時は注意してください。
