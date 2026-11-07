# 3Dキャラ制作手順（AI → Blender → Roblox）

自分で進めるための手順書。

**進める順番（11/7決定）：まずはゲームから。**
1. 今〜ローンチ：**ゲーム内ペット（ビートスピリット）として作るだけ**。Robux も Roblox Plus も不要
2. ローンチ後：人気のキャラが分かってから、ゲームの売上（コミュニティに入る Robux）でマーケットプレイスに出す。最初は人気の1体、または安く試せる2DのTシャツ（約90 Robux）から

モデルは最初からマーケットプレイスの規格（下の表）に合わせて作っておく。あとで出品するときに作り直さずに済む。

数値は Roblox 公式ドキュメント（2026/11/7 確認）による。制作開始時にもう一度確認すること。
- 規格：https://create.roblox.com/docs/art/accessories/specifications
- Blender の書き出し設定：https://create.roblox.com/docs/art/accessories/export-settings
- Blender と Studio の単位合わせ：https://create.roblox.com/docs/art/blender

## 守る規格（肩乗りアクセサリー。ペット用でも最初からこれに合わせる）

| 項目 | 規格 |
| --- | --- |
| メッシュ | **1つ**にまとめる（ヘッドホンも体と結合） |
| ポリゴン | **4,000 三角形以下** |
| 穴 | なし（watertight。開いた辺・裏面が見える箇所がない） |
| テクスチャ | **2048×2048 以下**（モバイル向けに 1024 推奨）。マテリアルは1つに焼き込む |
| サイズ（Normal 体型・肩の付け根＝Collar に付ける場合） | 幅 2.95 × 高さ 3.68 × 奥行き 3.24 スタッド以内 |
| 付ける位置 | `RightCollarAttachment`（腕を動かしても揺れない）。Studio の Accessory Fitting Tool が自動で設定する |

## 0. 準備

- [ ] Blender（4.x）：https://www.blender.org/download/
- [ ] 画像生成AI と 画像→3D のAIツールを選ぶ
  - **マーケットプレイスで売るので、生成物の商用利用・再販売が利用規約で認められているプランを使う**（楽曲ツールと同じ確認）
  - 3D化の候補：Roblox Studio 内蔵の生成機能（Assistant / Studio MCP の `generate_mesh`）、外部の画像→3Dサービス。外部ツールは GLB / FBX で書き出せるものを選ぶ
- [ ] Blender の単位：Scene Properties > Units > Unit Scale を **1.0** のまま（1 Blender 単位 ＝ 1 スタッド）

## 1. コンセプト画像を作る

3D化しやすい画像のコツ：**全身・正面・単色背景・パーツが重ならない・細すぎる部品がない**。

ヘッドホンは太くシンプルに（細いバンドはポリゴンを食い、穴の原因になる）。

プロンプトのひな形（英語の方が安定しやすい）：

```text
cute chibi mascot character, {モチーフ}, {体の色} body, {見た目のポイント},
wearing chunky rounded headphones, big round expressive eyes, short arms and legs,
simple rounded shapes, soft vinyl toy look, full body, front view, standing pose,
plain white background, no text, no logo, 3D render
```

ハルの例：

```text
cute chibi mascot character, small kitten spirit, pastel pink (#F7C6D9) body,
ear tips shaped like cherry blossom petals, wearing chunky rounded headphones in
neon pink (#FF4FA3), big round expressive eyes, short arms and legs, simple rounded
shapes, soft vinyl toy look, full body, front view, standing pose, plain white
background, no text, no logo, 3D render
```

- [ ] 気に入った案を3〜5枚に絞り、リポジトリの `assets/characters/haru/concept/` に保存
- [ ] 既存の有名キャラに似ていないか確認（画像検索で似た見た目が出てこないか）

## 2. 画像から3Dモデルを作る（AI）

- [ ] 正面画像を画像→3Dツールに入れる。横・後ろの画像も入れられるツールなら一緒に入れる
- [ ] GLB（または FBX）で書き出す

## 3. Blender で整える

1. **読み込み**：File > Import > glTF（または FBX）
2. **1つにまとめる**：部品が分かれていたら全部選んで `Ctrl+J`
3. **ポリゴンを減らす**：Modifier の Decimate で 4,000 三角形以下に（目安 3,000〜3,500。顔まわりが崩れたら Ratio を戻す）
4. **穴をふさぐ**：Edit Mode で Select > Select All by Trait > Non Manifold → 見つかった箇所を `F`（面を張る）で閉じる
5. **向きと大きさ**：正面を -Y（Blender の正面ビューで顔が見える向き）に、全体を高さ 1.5〜2.5 スタッド程度に。最後に `Ctrl+A` > All Transforms で確定
6. **テクスチャを1枚に**：UV を展開（Smart UV Project）→ Cycles の Bake（Diffuse、Color のみ）で 1024×1024 の1枚に焼き込み、マテリアルを1つにする
7. **チェック**：Scripting タブで [`tools/blender/check_accessory.py`](../tools/blender/check_accessory.py) を開いて実行。`NG` がゼロになるまで直す

## 4. 書き出す（FBX）

File > Export > FBX：
- Path Mode：**Copy**、隣の **Embed Textures** をオン
- Transform > Apply Scalings：**FBX Unit Scale**
- Forward：**Z Forward**、Up：**Y Up**
- Modifier は適用済みにしておく

（glTF で書き出す場合はスケール設定は不要）

- [ ] 書き出したファイルを `assets/characters/haru/export/haru.fbx` に保存

## 5. Studio に取り込む（ゲーム内ペット用）← 今はここがゴール

1. File > **Import 3D** で FBX を読み込む
2. できた MeshPart の名前をキャラ名（例：`Haru`）にして、ここで止めて見せてください
3. ペットとして連れ歩く処理・ふわふわ揺れる動き・夜の発光はこちらでコードを書く（ペットは発光を足しても費用はかからない）

---

ここから下は **ローンチ後**（人気キャラが分かってから）。

## 6. アクセサリーにする

1. Avatar タブ > **Accessory Fitting Tool** を開き、5 で取り込んだモデルを選ぶ
2. 種類を **Shoulder**、付ける位置を **RightCollarAttachment** に
3. マネキンで Classic / Normal / Slender の3体型を確認（はみ出していないか、顔に被っていないか）
4. 完成したら Accessory を保存

## 7. マーケットプレイスに出す

費用はゲームの売上（コミュニティの Robux）でまかなう。

- 本人確認（ID）済みであること
- **Roblox Plus に加入していること**（出品と販売継続の条件。解約すると販売停止）。2段階認証もオン
- アップロード料 80 Robux（発光マスクを使うと 500）。審査に落ちても返金なし
- 出品時の前払い 1,000 Robux（Shoulder・通常アイテム）。売上から回収
- 出品前に：サムネイルの見え方、価格、コミュニティ名義で出せるか- 安く試すなら：キャラ柄の2DのTシャツ（アップロード料80＋前払い10＝約90 Robux。Plus は必要）
