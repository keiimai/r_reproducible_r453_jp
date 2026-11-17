# R 4.5.3 解析環境

研究プロジェクトを起こすための、R と RStudio Server の実行環境と、再現性の記録層のテンプレートです。使う人のパソコンに入れるのは Docker Desktop だけで、R・RStudio Server・R のパッケージは、そのパソコンで作る Docker のイメージの中に入ります。

> **解析のコードは入っていません。** 第4〜5層（解析の部品と実行）はプロジェクトが書きます（→ [`docs/LAYERS.md`](docs/LAYERS.md)）。
>
> **このテンプレートから起こしたプロジェクトでは、このファイルをプロジェクトの概要に書き換えてください。**

## 使い方

| するとき | すること |
|---|---|
| プロジェクトを起こす | [`docs/SETUP.md`](docs/SETUP.md) の手順 1〜6（取り出す → git 化 → `make rename` → `make build` → `make verify` → `make hooks`） |
| 解析する | `make up` で RStudio Server を起こし、出た `http://localhost:<番号>` を開く。`notebooks/` にノートブック（`.qmd`）を書く（書き方 → [`notebooks/README.md`](notebooks/README.md)） |
| 結果を出す | コミットしてから `make render QMD=notebooks/<名前>.qmd`。HTML は `outputs/reports/<実行 ID>/` にできる |
| 終える | `make up` の窓で Ctrl-C か、`make down` |
| 命令を調べる | `make help` |

## できること

- どのパソコンでも、同じ版の R とパッケージで動きます（R の版・パッケージの取得元の日付・`renv.lock` で固定）。
- 解析を実行するたびに、記録が自動で残ります。どのコード（git のコミット）・どの入力（ファイルの SHA-256）・どの環境・どの設定から、どの成果物ができたかを辿れます。全実行の台帳（`outputs/repro/runs.csv`）も作れます。
- ノートブックを 1 回で実行と描画をし、1 ファイルで完結する HTML を、実行 ID の付いたフォルダに出します。失敗した実行は `failed` として残ります。
- コミットの前に、データ・成果物・秘密情報（`.env`・鍵・トークン）が Git に入るのを止めます。
- RStudio Server でも、VS Code（Dev Container）でも、同じイメージで書けます。
- lint・テスト・記録層の疎通確認を `make verify` 1 つで、GitHub の CI でも同じ検査を走らせられます。

## 仕組み

テンプレートは 5 つの層でできていて、第1〜3層をテンプレートが、第4〜5層をプロジェクトが持ちます。プロジェクトが第1〜3層に書いてよいのは、決まった 10 の「余白」だけです（→ [`docs/LAYERS.md`](docs/LAYERS.md)）。

| 層 | 中身 | 書く人 |
|---|---|---|
| 第5層 解析の実行 | ノートブック・設定・研究の文書 | プロジェクト |
| 第4層 解析の部品 | `R/project_*.R` とそのテスト | プロジェクト |
| 第3層 再現性の記録 | 記録層 `R/repro.R`・`DESCRIPTION`・`renv.lock`・`.Rprofile`・ノートブックの書式 | テンプレート |
| 第2層 開発環境 | `Makefile`・コミット前の検査・CI・ディレクトリの骨格 | テンプレート |
| 第1層 コンテナ | `Dockerfile`・`docker-compose.yml`・`.devcontainer/`・`docker/` | テンプレート |

```
ブラウザー ─ http://localhost:<番号>（RStudio Server。このパソコンからだけ開ける）
コンテナ <名前>_dev（名前は docker-compose.yml の name:。/app ＝ このフォルダ）
  ├─ R 4.5.3 と、renv.lock どおりのパッケージ（/opt/renv/library）
  ├─ RStudio Server・Quarto
  └─ make check・make render などは、同じイメージの使い捨てのコンテナで走る
```

`make` はホスト（パソコンのターミナル）で打ちます。R を使う命令は、自動でコンテナの中に入り直して走ります。ホストに R は要りません。

## 記録

ノートブックが `repro_run()` と `repro_finish()` で実行を挟むと、1 回の実行ごとに記録ができます（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)）。

| 置き場所 | 中身 |
|---|---|
| `outputs/repro/<実行 ID>/<実行 ID>_run.json` | 記録（コミット・入力と成果物の SHA-256・環境・状態） |
| `outputs/repro/<実行 ID>/<実行 ID>.config.yaml` | 使った設定（既定値まで含む） |
| `outputs/repro/runs.csv` | 全実行の台帳（`make runs` が作り直す） |
| `outputs/reports/<実行 ID>/` | `make render` が描いた HTML |

`data/`・`outputs/`・`models/` の中身は Git で追跡しません。

## 技術スタック

| 項目 | 採用 | 理由 |
|---|---|---|
| 言語 | [R](https://www.r-project.org/) 4.5.3（[`rocker/rstudio:4.5.3`](https://rocker-project.org/images/versioned/rstudio.html)） | 4.5 系の最終パッチ |
| パッケージ管理 | [renv](https://rstudio.github.io/renv/) + `renv.lock` | 版を固定する |
| コンテナ | [Docker](https://docs.docker.com/)（`linux/arm64`） | Apple Silicon のまま動かす |
| 対話環境 | [RStudio Server](https://docs.posit.co/ide/user/) と [VS Code](https://code.visualstudio.com/)（[Dev Container](https://code.visualstudio.com/docs/devcontainers/containers)） | 同じイメージ。ホストに R を入れない |
| レポート | [Quarto](https://quarto.org/docs/computations/r.html)（`.qmd` → HTML） | 実行と描画を 1 回に揃える |
| 実行の記録 | 自作の記録層（`R/repro.R`）+ `make runs` | 実行ごとに、`inputs` に渡したファイルと成果物の SHA-256・環境・コミットを残す（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)） |
| 品質 | [testthat](https://testthat.r-lib.org/)・[lintr](https://lintr.r-lib.org/) | lint・テスト |

## 文書

| 文書 | 中身 |
|---|---|
| [`docs/SETUP.md`](docs/SETUP.md) | プロジェクトの起こし方（上から順に行う）と、起動の 2 経路 |
| [`docs/LAYERS.md`](docs/LAYERS.md) | 5 層の見取り図（どのファイルがどの層か・余白・ファイルを足す場所・テンプレートの更新の取り込み方） |
| [`docs/DOCKER.md`](docs/DOCKER.md)・[`docs/WORKSPACE.md`](docs/WORKSPACE.md)・[`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) | 第1層・第2層・第3層の仕様書 |
| [`notebooks/README.md`](notebooks/README.md)・[`data/README.md`](data/README.md) | ノートブックの書き方と記録の取り方・データの置き方 |
| `CHANGELOG.md` | プロジェクトの判断の記録（取り込んだテンプレートの版も書く） |

## ライセンスと引用

- コードは [MIT](https://opensource.org/license/mit)（`LICENSE`）です。手順書・動画などの教材を人に渡すプロジェクトは、教材だけを [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.ja) にします（根に `LICENSE-docs` を足す）。
- ビルドのときに取ってくるもの（Docker のベースイメージ・R・R のパッケージなど）は、配るものに入れていません。それぞれの作者の条件に従います。
- この環境を引用するときは、`CITATION.cff` の情報を使ってください。

## AI の使用

コードと文書は、AI のコーディング支援（Anthropic の [Claude Opus 5.5](https://www.anthropic.com/claude/opus) を [Claude Code](https://code.claude.com/docs/en/overview) で使った）を道具として使って書いた。作者が作業を指示し、中身に責任を持つ（AI は著者にしない）。動きは `make verify`（`renv.lock` の検査・lint・テスト・記録層の疎通確認）で確かめている。
