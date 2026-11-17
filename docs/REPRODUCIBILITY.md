# 第3層 — 再現性の記録

第3層は、その数値がどのコード・どの入力・どの環境・どの設定から出たかを記録する。

---

## 1. 構成と保証の範囲

| ファイル | 役割 |
|---|---|
| [`DESCRIPTION`](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#The-DESCRIPTION-file)・[`renv.lock`](https://rstudio.github.io/renv/articles/lockfile.html) | 依存を宣言し、版を固定する（→ 5 節） |
| `R/repro.R` | 記録層。実行の記録・乱数の種の固定（`repro_set_seed()`）・設定の読み込み・BOM 付きの CSV の書き出し（`repro_write_csv()`）・`make smoke` と `make runs` の中身 |
| [`.Rprofile`](https://search.r-project.org/R/refmans/base/html/Startup.html) | R を起動したときの決まり。末尾の見出しの下は第4〜5層の余白（→ 下の注意） |
| `tests/testthat/test-repro.R`・`helper-load.R` | 記録層のテストと、テストの前に `R/` を読み込む helper |
| `notebooks/README.md`・`notebooks/_metadata.yml`・`notebooks/_project_author.yml`・`notebooks/styles.css` | ノートブックの書き方の約束と、HTML の書式（それぞれの役目 → [`notebooks/README.md`](../notebooks/README.md)「構成」） |

`.Rprofile` の余白（書かないもの → [`LAYERS.md`](LAYERS.md)「第4〜5層の『余白』」）に書くときの注意:

- リポジトリの根で起動するすべての R が読む（RStudio・`Rscript`・`make test`・`make render` の描画の中の R など）。対話のときだけ、または RStudio のときだけ動かしたい処理は、[`interactive()`](https://search.r-project.org/R/refmans/base/html/interactive.html) などで分ける。
- `--vanilla` で起動した R（コミット前の検査・`make lock` の中の R）と、根の外で起動した R は、`.Rprofile` を読まない。

| | 保証するか |
|---|---|
| 同じ環境で同じ結果が出る | 環境の側はする（依存・ロケール・スレッド数・乱数の種類の固定）。解析が種を渡しているかと、2 回走らせて一致するかは、プロジェクトが確かめる |
| 成果物がどのコード・どの入力・どの設定から出たか辿れる | する（コミット・`inputs` に渡したファイルと成果物の SHA-256・解決済みの設定を記録する） |
| データの差し替えに気づける | する（`inputs` に渡したファイルの SHA-256）。差し替える前のデータは復元しない（データは版管理しない） |
| ダミーの数字が結果として出回らない | 記録の `data_mode` と、成果物に付けた実行 ID（名前の頭かフォルダ）で見分ける |
| 別の CPU で下位桁まで一致する | しない（arm64 と amd64 では、数値計算の実装が違う。CI の `checks` は amd64） |

---

## 2. 記録の流れ

入口（第5層のノートブック）が、`repro_run()` と `repro_finish()` で実行を挟む（書き方は `notebooks/README.md`）。

- 設定で記録層が読むのは `seed`・`experiment_name`・`data.mode`・`repro`（`enabled`・`quiet`）だけで、ほかのキーはそのまま持ち越して記録する。省いたキーは既定になる（→ `R/repro.R` の `repro_config_defaults()`）。`repro.quiet: true` にすると、始めと終わりの表示を出さない
- 失敗を記録に残すには、`repro_fail(state, error)` を呼ぶ（記録を `status: failed` で終え、`error` に理由（条件か文字）を残す。例: `tryCatch(本体, error = function(e) { repro_fail(state, e); stop(e) })`）
- 台帳（`runs.csv`）の列になるのは、`state$ledger` のうち長さ 1 の値だけである。どの実行にもある列と同じ名前は、列にしない（知らせは出ない）
- 記録を取らないときは設定を `repro.enabled: false` にする（`repro_finish()`・`repro_fail()` は何もしない）
- 実行 ID は `<YYYYMMDD_HHMMSS>_<名前>_<4 桁の数>`（コンテナの時刻帯。→ 下）で、`outputs/` に書く成果物は、名前の頭に実行 ID を付けるか、実行 ID のフォルダ（`outputs/figures/<run_id>/` など）に入れる
- `<名前>` は、ノートブックを描いている間は `.qmd` の名前、それ以外（チャンクを手で走らせたときや `make smoke`）は設定の `experiment_name` である。記録の `experiment_name`（`make runs EXP=` で絞る名前）は、どのノートブックが読んでも設定の値のまま残る。次の段が読む `data/interim/`・`data/processed/`・`models/` のファイルは決まった名前で書き、前の段の記録の `artifacts` と次の段の `inputs` の SHA-256 で辿る
- 実行 ID と記録の時刻は、コンテナの時刻帯（`TZ`。選び方と既定 → [`DOCKER.md`](DOCKER.md) 3 節）で付ける。時刻帯は、プロジェクトの初めに決めて途中で変えず、共同研究者とも同じにする（実行 ID の名前には時差が入らないので、途中で変えると、実行 ID が実行した順に並ばなくなる）
- 描画した HTML は、記録の成果物に載らない

```
outputs/repro/<run_id>/<run_id>_run.json      記録
outputs/repro/<run_id>/<run_id>.config.yaml   解決済みの設定（既定値まで含む）
outputs/repro/runs.csv                        実行台帳（make runs が作り直す。BOM 付きの UTF-8）
```

記録と解決済みの設定は始めた時点で書かれ（記録は `status: running`）、記録は終わりに上書きされる。`make render` は、成功したときだけ HTML を `outputs/reports/<run_id>/` に写す。`make render` が失敗すると（描画の段で落ちても）、記録を `failed` に書き換え、名前かフォルダにその実行 ID を含む途中の成果物（`outputs/` の下）を `outputs/repro/<run_id>/partial/` に移す。［Render］が途中で止まるか、`make down` で止めるか、チャンクを手で走らせて `finish` のチャンクの前にやめると、記録は `status: running` のまま残る。

---

## 3. 記録の読み方と再現

1. `git_dirty` が `false` なら、[`git checkout <git_commit>`](https://git-scm.com/docs/git-checkout) でそのコードに戻る（`true` なら、そのコードはもう無い。`git_commit`・`git_dirty` が null なら、Git の外で走らせたか、Git が失敗した）
2. `environment` の `renv_lock_sha256` と `build_info` で、同じ `renv.lock` とベースイメージの環境を作る（`make build`）
3. `inputs` の SHA-256 と、手元のデータを突き合わせる
4. 同じノートブックを、そのコミットのまま `make render` で描き直し（設定もそのコミットのものを読む）、`artifacts` の SHA-256 と突き合わせる。書き出した時刻を中に持つ形式（SAV・XLSX など）は、読み込んだ中身で比べる

---

## 4. 注意

- ロケールは、[factor](https://search.r-project.org/R/refmans/base/html/factor.html) の水準順（回帰の参照水準と係数の符号）を決める。`LANG`・`LC_ALL` は `C.UTF-8` に固定してある（→ [`DOCKER.md`](DOCKER.md) 2 節の層 2）。参照水準を決める変数は `factor(x, levels = c(...))` で明示する
- BLAS（[OpenBLAS](https://www.openmathlib.org/OpenBLAS/docs/runtime_variables/)）と OpenMP は、R の起動前の環境変数でスレッド数を決める（既定は 1。→ [`DOCKER.md`](DOCKER.md) 3 節。最終結果を出す実行では 1 のままにする）。`.Renviron` や `Sys.setenv()` では効かない。RStudio のセッションでは、`.Rprofile` が [`RhpcBLASctl`](https://cran.r-project.org/package=RhpcBLASctl) で設定し直し、1 でなければ注意を出す
- 並列化（[`parallel`](https://search.r-project.org/R/refmans/parallel/html/parallel-package.html)）は種を壊す。するなら [`parallel::clusterSetRNGStream()`](https://search.r-project.org/R/refmans/parallel/html/RngStream.html) で乱数列を配り、しないなら逐次で回す
- 設定は `repro_config_load()`・`repro_read_yaml()` で読む（UTF-8 として読み、YAML 1.1 で論理値や文字に化ける書き方（[論理値](https://yaml.org/type/bool.html)・[小数](https://yaml.org/type/float.html)の決まり）は、止めるか警告する）
- 人が開く CSV は、BOM 付きの UTF-8 で書く（`repro_write_csv()`）。日本語版 Excel は BOM の無い CSV を Shift_JIS として読み、日本語が化ける（[Microsoft の説明](https://support.microsoft.com/ja-jp/excel/opening-csv-utf-8-files-correctly-in-excel)）。`make lint` が、BOM を付けない書き出しを止める（止める関数 → `.lintr`）。R で読み直すときは `fileEncoding = "UTF-8-BOM"` を付ける
- 論文に載る結果は、記録を始めて終えるチャンク（`repro_run()`・`repro_finish()`）で包んだノートブックから出す。コミットしてから、記録を取って（`repro.enabled: true`）、`make render` で描く（図は、描き方でバイトが変わる）

---

## 5. 依存（`DESCRIPTION` と `renv.lock`）

依存は `DESCRIPTION` に宣言し、`renv.lock` に固定する（作り直し方 → [`WORKSPACE.md`](WORKSPACE.md) 2 節、取得元 → [`DOCKER.md`](DOCKER.md) 2 節）。版を決めるのは、`Dockerfile` の `BASE_IMAGE` と `P3M_SNAPSHOT`、`renv.lock` である（OS のパッケージの版は固定しない）。

| 欄 | 中身 |
|---|---|
| `Imports` | 記録層が使う [yaml](https://yaml.r-lib.org/)・[digest](https://eddelbuettel.github.io/digest/)・[jsonlite](https://cran.r-project.org/package=jsonlite) |
| `Suggests` | テスト・lint・描画・parquet の読み書きと、対話セッションのスレッド数の設定に使う [testthat](https://testthat.r-lib.org/)・[withr](https://withr.r-lib.org/)・[lintr](https://lintr.r-lib.org/)・[RhpcBLASctl](https://cran.r-project.org/package=RhpcBLASctl)・[knitr](https://cran.r-project.org/package=knitr)・[rmarkdown](https://pkgs.rstudio.com/rmarkdown/)・[stringi](https://stringi.gagolewski.com/)・[stringr](https://stringr.tidyverse.org/)・[tidyverse](https://www.tidyverse.org/)（データの整形と図）・[nanoparquet](https://nanoparquet.r-lib.org/) |
| `Config/Needs/project` | **第4〜5層の余白**（→ [`LAYERS.md`](LAYERS.md)「第4〜5層の『余白』」） |

`renv/activate.R` は置かない（`renv::init()` もしない）。
