# KMZ Tools for Google My Maps

複数のKMZを結合して **[Google My Maps](https://mymaps.google.com)** で色・スタイルが正しく出るように整えるツール群です。  
スクリプトはBash版とPowerShell版があり、それぞれ`bash/`と`powershell/`ディレクトリにまとめています。  
<br>
`bash/merge_kmz.sh`は単体で動作します。  
`bash/calcKML-selectKMZ.sh`を使う場合は、**同じディレクトリ**に`bash/merge_kmz.sh`を置いてください。  
PowerShell版も同様に`powershell/`内で利用します。

## 機能概要

- **merge_kmz.sh**

  - 複数の KMZ を 1 つの KMZ に結合。
  - 各ルートに色を順番に割り当て（ABGR 8 桁、Google My Maps 向け）。
  - 既存の `<styleUrl>` を消してから新しい `<Style>` を **Placemark より前**に定義（Google My Maps が前方参照できない問題の回避）。
  - **単体で実行可能**。

- **calcKML-selectKMZ.sh**
  - 入力 KMZ 群を解凍し、含まれる **KML のリストとサイズ**を表示。
  - 対話式に KML を選び、**選ばれた KML を含む KMZ**だけを `merge_kmz.sh` に渡して結合。
  - `merge_kmz.sh` への依存あり。**2 つのスクリプトは同じディレクトリ（本リポジトリでは bash/ または powershell/）に配置**してください。

## 動作環境 / 依存コマンド

- OS: macOS または Linux（Windows は WSL 推奨）
- Bash 3 以上（macOS 付属の bash でも動作）
- 利用コマンド: `unzip`, `zip`, `awk`, `sed`, `find`, `wc`, `tr`, `hexdump`
- Google マイマップでの読み込みを想定（KML/KMZ 形式）

## インストール

```bash
# クローン後（またはダウンロード後）
chmod +x bash/*.sh
```

## 使い方

### A. `merge_kmz.sh`（単体で実行可能）

```
Usage: ./bash/merge_kmz.sh OUTPUT.kmz INPUT1.kmz [INPUT2.kmz …]
例:    ./bash/merge_kmz.sh merged.kmz dir/25*.kmz
```

- 実行すると「色の見本」を表示し、**最初の KMZ に使う開始色**を尋ねます（1〜色数）。
  Enter だけ押すと 1 番の色から順に割り当てます。
- **非対話**（パイプやリダイレクト）では自動で 1 番から開始します。
- ルート名は KMZ ファイル名から拡張子 `.kmz` を除き、**先頭の `_` までを取り除いた部分**を使います。
  例: `2205060502_partFileName.kmz` → `partFileName`。
- 出力: `OUTPUT.kmz`

### B. `calcKML-selectKMZ.sh`（対話式フィルタ → 結合）

```
Usage: ./bash/calcKML-selectKMZ.sh OUTPUT.kmz INPUT1.kmz [INPUT2.kmz …]
例:    ./bash/calcKML-selectKMZ.sh merged.kmz dir/25*.kmz
```

1. 各 KMZ 内の **KML 一覧**（番号, サイズ\[bytes], パス）を表示。
2. 範囲指定（例: `1-3 7 10-12`）、`all`、`list`、`q` に対応。
3. 選んだ KML を **含む KMZ を一意化**して `merge_kmz.sh` に渡し、結合します。
4. `merge_kmz.sh` が **同じディレクトリ（bash/ または powershell/）**にあり、実行権限が必要です。

## 注意点・既知の仕様

- My マップ側の制限により、非常に大きな KML/KMZ は読み込みに時間がかかったり、分割が必要な場合があります。
- 色指定は KML の仕様に合わせた **ABGR**（アルファ＋青緑赤）8 桁です。
- 既存の `<Style>` と `<styleUrl>` は統一のため除去し、新しいスタイルを先に定義します。
- `calcKML-selectKMZ.sh` で複数 KML を選んでも、**同じ KMZ に入っている場合は 1 回だけ渡します**（重複排除）。

## サンプル

```bash
# A. そのまま結合
./bash/merge_kmz.sh output.kmz tracks/25*.kmz

# B. KML を見てから絞り込み → 結合
./bash/calcKML-selectKMZ.sh output.kmz tracks/25*.kmz
```
