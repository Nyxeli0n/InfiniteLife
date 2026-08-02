# Infinite Life

Infinite Lifeは、コンウェイのライフゲームをMetalでモノクロ描画する、macOS用ライブ壁紙アプリです。セルをチャンク単位で管理することで、表示領域の外まで世界を広げられるようにしています。

## 動作環境

- macOS 13以降
- XcodeまたはCommand Line Tools
- Metal対応Mac

## ビルド

ビルドスクリプトを実行します。

```bash
./scripts/build.sh
open build/InfiniteLife.app
```

または、Xcodeで `InfiniteLife.xcodeproj` を開き、`InfiniteLife` スキームを実行します。

アプリはメニューバーで動作し、Dockには表示されません。

## 配布について

`scripts/build.sh` は手元で動作確認するためのビルドです。ほかの人へ配布する場合は、XcodeでDeveloper ID署名を行い、Hardened Runtimeを有効にした状態でAppleの公証を通してください。署名していないアプリをそのまま配布することは想定していません。

## 実装

- 64×64セルの疎なチャンクで、実質的に無限の世界を構成します。
- コンウェイのB3/S23ルールを基礎に、定期的な再投入と長時間残る静的構造の除去を行います。
- 各ディスプレイに、クリックを透過するデスクトップ階層のMetal描画面を配置します。
- シミュレーション状態を終了時に保存し、次回起動時に復元できます。
- フレームレートは30 fps、60 fps、電源状態に応じた自動選択から設定できます。
