# KMZ Tools for Google My Maps

複数の KMZ を結合して **Google マイマップ** で色・スタイルが正しく出るように整えるツール群です。  
`merge_kmz.sh` は単体で動作します。  
`calcKML-selectKMZ.sh` を使う場合は、**同じディレクトリ**に `merge_kmz.sh` を置いてください。

---

## 機能概要

- **merge_kmz.sh**

  - 複数の KMZ を 1 つの KMZ に結合。
  - 各ルートに色を順番に割り当て（ABGR 8 桁、Google My Maps 向け）。
  - 既存の `<styleUrl>` を消してから新しい `<Style>` を **Placemark より前**に定義（Google My Maps が前方参照できない問題の回避）。
  - **単体で実行可能**。

- **calcKML-selectKMZ.sh**
  - 入力 KMZ 群を解凍し、含まれる **KML のリストとサイズ**を表示。
  - 対話式に KML を選び、**選ばれた KML を含む KMZ**だけを `merge_kmz.sh` に渡して結合。
  - `merge_kmz.sh` への依存あり。**2 つのスクリプトは同じディレクトリに配置**してください。

---

## 動作環境 / 依存コマンド

- OS: macOS または Linux（Windows は WSL 推奨）
- Bash 3 以上（macOS 付属の bash でも動作）
- 利用コマンド: `unzip`, `zip`, `awk`, `sed`, `find`, `wc`, `tr`, `hexdump`
- Google マイマップでの読み込みを想定（KML/KMZ 形式）

---

## インストール

```bash
# クローン後（またはダウンロード後）
chmod +x merge_kmz.sh calcKML-selectKMZ.sh
```
