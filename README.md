# Beat Garden（BEAT WORKS #1）

「音で育てて、音で守る、音で奪う」育成×収集×リズムのRobloxゲーム。

- 詳細仕様書: [docs/spec.md](docs/spec.md)

## 開発環境のセットアップ

ツールのバージョンは `rokit.toml` で固定しています（Rojo / StyLua / selene）。

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
