# Beat Garden（BEAT WORKS #1）

「音で育てて、音で守る、音で奪う」育成×収集×リズムのRobloxゲーム。

- 詳細仕様書: [docs/spec.md](docs/spec.md)
- 3Dキャラ制作手順: [docs/3d-pipeline.md](docs/3d-pipeline.md)
- キャラクター方針: [docs/character-direction.md](docs/character-direction.md)

## 開発環境のセットアップ

ツールのバージョンは `rokit.toml` で固定しています（Rojo / StyLua / selene / Lune）。

1. [Rokit](https://github.com/rojo-rbx/rokit) をインストール
2. リポジトリ直下でツールを入れる

   ```bash
   rokit install
   ```

3. Studioに Rojo プラグインを入れる（Rojo 7.7.1 と同じバージョン）

   ```bash
   rojo plugin install
   ```

4. 開発サーバーを起動し、Studioの Rojo プラグインから Connect

   ```bash
   rojo serve
   ```

VS Code を使う場合は `.vscode/extensions.json` の推奨拡張（Rojo、luau-lsp、StyLua、selene）を入れてください。

## よく使うコマンド

placeファイルを書き出す（CI・Place Publishing API用）:

```bash
rojo build -o BeatGarden.rbxl
```

テスト（`tests/*.spec.luau`、Lune で実行）:

```bash
lune run tests/run
```

整形とLint:

```bash
stylua src
```

```bash
selene src
```

## フォルダ構成と Roblox 上の配置

| フォルダ | Roblox上の場所 | 内容 |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` | サーバー・クライアント共通（Palette など） |
| `src/server` | `ServerScriptService.Server` | サーバーロジック（`init.server.luau` が入口） |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | クライアント（`init.client.luau` が入口） |

ファイル名の規則（Rojo）: `*.server.luau` = Script、`*.client.luau` = LocalScript、`*.luau` = ModuleScript。

## リズムエンジン（試作）

`src/shared/RhythmEngine` にあります。Roblox の Instance を使わない純粋なロジックなので、クライアント・サーバー・Lune のテストで同じコードが動きます。

| モジュール | 役割 |
| --- | --- |
| `Judge` | 判定窓（Perfect ±45 / Great ±90 / Good ±135ms）と、ズレ列からの集計 |
| `Chart` | 譜面区間（segment）の検査と並べ替え、譜面オフセットの適用 |
| `Session` | 1回のプレイ。曲の現在時刻を渡すと判定・Miss・コンボを返す。遅延補正もここ |
| `Validator` | サーバー側の検証。ノーツ数・ズレの範囲・所要時間・人間離れした精度をチェックし、集計はサーバーで計算し直す |
| `Calibration` | 遅延キャリブレーション（拍に合わせたタップから推奨 latencyMs を出す） |

クライアントがサーバーに送るのは「ノーツごとのズレ（ms）、Missは false」の列です。判定数やコンボはサーバーがこの列から計算し直すので、クライアントの申告は信用しません。

### 試す（Studio / Roblox アプリ）

試作は `src/shared/Dev/Flags.luau` の `RhythmPrototype` で切り替えます。`true` の間は公開した place でも動くので、スマホの Roblox アプリでも確認できます（正式公開前に `false` に戻す）。

1. `rojo serve` して Studio から Connect し、Play（アプリで確認するときは place を公開して参加）
2. 楽曲セレクト画面で曲をタップして選ぶ。選択中の曲のプレビューが流れる（PC は ↑ / ↓ でも選べる）
3. Easy / Normal / Hard をタップ（PC は `1` / `2` / `3`）で、選んだ曲のテスト譜面が始まる
4. PC は D / F / J / K、モバイルは画面下の4ボタン、ゲームパッドは L2 / L1 / R1 / R2
5. 終了すると Output に結果とサーバー検証の結果が出る

遅延補正を試すときは、Play 中に LocalPlayer の属性 `LatencyMs` を設定してください（例: 60）。

### 楽曲

曲の一覧は `src/shared/Songs.luau` です（仕様書の Master_Songs と同じ項目）。再生は `src/client/SongPlayer.luau` が担当します。

- **音源がまだない曲**（`audioAssetId` が空）は、Roblox 内蔵の効果音を音程を変えて鳴らす「デモ音源」で再生します。アップロードも権限設定もいらない仮の曲です。いま入っている3曲はすべてこれです
- **本物の音源を使うとき**は、音声を Roblox にアップロードしてこのエクスペリエンスでの使用を許可し、`audioAssetId`（`rbxassetid://...`）、メドレー内の範囲 `regionStartMs` / `regionEndMs`、譜面のズレ `offsetMs`、プレビュー位置 `previewStartMs` を入れます
- 音源が8秒たっても始まらない場合（IDの間違い・使用許可なしなど）は Output に警告を出し、音なしで譜面だけ進めます
