# 第2層 — 開発環境

第2層は、どこに何を置き、何を機械的に止めるかだけを決める。

---

## 1. 構成

```
configs/
data/             raw / raw/dummy / interim / processed / external         ← 中身は Git 追跡外
docs/definition/
models/                                                                    ← 同上
outputs/          tables / figures / metrics / reports / repro             ← 同上
```

`data/` の中のフォルダの使い方は [`data/README.md`](../data/README.md)、ほかのフォルダにどの層のファイルを置くかは [`LAYERS.md`](LAYERS.md)。

| ファイル | 役割 |
|---|---|
| `Makefile` | 作業の入口（→ 2 節） |
| `project.mk` | プロジェクトが足す `make` の命令（第4〜5層の余白。書いてよいもの → [`LAYERS.md`](LAYERS.md)。仕組み → 2 節） |
| `setup.R` | テンプレートと同じディレクトリの構成を、無いものだけ作る |
| `.gitignore` | 人が書いたものだけを追跡する（[`.gitignore` の説明書](https://git-scm.com/docs/gitignore)）。鍵の `*.key` は Keynote のスライドも外すので、スライドは PDF などに書き出して渡す。末尾の見出しの下は、プロジェクトが行を足してよい（第4〜5層の余白。→ [`LAYERS.md`](LAYERS.md)） |
| `.editorconfig` | 字下げ・改行・文字コードの決まり（[EditorConfig](https://editorconfig.org/)） |
| `.lintr` | lint の決まり（[lintr](https://lintr.r-lib.org/articles/lintr.html#the--lintr-file) の既定から変えた点だけを書く） |
| `.vscode/settings.json` | VS Code の[ワークスペースの設定](https://code.visualstudio.com/docs/configure/settings#_workspace-settings) |
| `.githooks/pre-commit`・`tools/precommit_checks.R` | コミット前の検査（→ 3 節） |
| `tools/make_lockfile.R` | `make lock` と `make lock-check` の本体（→ 2 節） |
| `.github/workflows/ci.yml` | CI（→ 4 節） |
| `LICENSE` | [MIT](https://opensource.org/license/mit) |

---

## 2. `Makefile`

`make` だけを打つと一覧が出る（[GNU Make の説明書](https://www.gnu.org/software/make/manual/make.html)）。

コンテナで動く命令は、ホストから打つと [`docker compose run --rm --user rstudio task make <target>`](https://docs.docker.com/reference/cli/docker/compose/run/) に自動で入り直す。

プロジェクトが足す命令は、根の `project.mk` に書く。`Makefile` が最後に読み込む（無ければ何もしない）。変数の名前は調べないので、テンプレートと同じ名前の変数（`IMAGE`・`PLATFORM` など）を書くと、テンプレートの命令が打つコマンドではその値に置き換わり、先に値を決めた変数（`BASE_TAG` など）は元のまま残って、食い違う。`project.mk` の命令は打った所（ホストかコンテナ）で動くので、コンテナで動かすものは `docker compose run --rm --user rstudio task …` と書く。

`make lint` は `R/`・`tests/`・`tools/`・`docker/`・`notebooks/`（`.qmd` は R のチャンク）に掛かる（[`lintr::lint_package()` と `lint_dir()`](https://lintr.r-lib.org/reference/lint.html)）。

`make lock` は、`DESCRIPTION` が宣言したものと renv を、依存（`Suggests` まではたどらない）ごとプロジェクトライブラリに入れ、読み込めるかを確かめてから `renv.lock` に書く。`make lock-check` は `renv.lock` を書き換えずに、宣言したものが版の指定どおりに載り、依存の足りないものと残りものが無いかを確かめる。

---

## 3. コミット時の検査

`make hooks` が `core.hooksPath` を `.githooks` にし（git の [githooks の説明書](https://git-scm.com/docs/githooks)）、マージのコミットにも同じフックを掛ける（git の版 → [`SETUP.md`](SETUP.md) 0 節。[git hook](https://git-scm.com/docs/git-hook)）。R の検査（`tools/precommit_checks.R`）はイメージの R で走るので、Docker が動いていて、今の名前のイメージがあるときだけ、コミットできる（`make rename` の後は `make build` する）。`make hooks-all` は追跡中の全ファイルに同じ検査を掛ける。

| 検査 | 止めるもの |
|---|---|
| `renv.lock` の追跡 | `renv.lock` を入れ忘れたコミット |
| `data/`・`outputs/`・`models/` の下 | データと成果物（`data/README.md`・`.gitkeep` は通す） |
| `.env` | 秘密情報を書くファイル（`.env.example` は通す） |
| `data/` の外のデータの形式 | CSV・Excel・SPSS・Stata・SAS・RDS・Parquet・pickle・圧縮ファイル（zip・gz・tar など）など（`docs/definition/`・`configs/`・`tests/testthat/` は通す） |
| `.gitignore` が外すファイル | 追跡しているのに `.gitignore` に当たるもの。`git add -f` で入れたものと、余白に行を足す前から追跡していたもの（`docs/definition/`・`configs/`・`tests/testthat/` のデータの形式は通す） |
| 2 MB を超えるファイル・秘密鍵・よく知られたトークン・秘密情報らしい名前に書いた値（コードでは引用符の中の値） | 秘密情報とデータの混入 |
| 大文字小文字だけが違う名前 | macOS・Windows と Linux での衝突 |
| 衝突の印 | `<<<<<<<` などを残したまま仕上げたマージ・cherry-pick・revert（`git rebase --continue` は git がフックを呼ばないので、掛からない） |
| `docker-compose.yml` の `name:` がテンプレートの値のまま | 止めずに知らせる（`make rename` の後に `git add` を忘れたコミット） |
| R・YAML（`CITATION.cff` を含む）・JSON の構文 | 壊れたファイル |
| `R/` の `repro.R` 以外が `repro_run()`・`repro_finish()`・`repro_fail()` を呼ぶこと | 記録の流れを第4層の関数が握ること（→ [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 2 節） |
| 行末の空白と末尾の改行 | 書式のゆれ（Markdown と表の形のデータの行末の空白は見ない。作業ツリーがステージと同じなら直してから止めるので、`git add` し直す） |

---

## 4. CI

`ci.yml`（[GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)）は、手で走らせたときだけ走る。

| ジョブ | 見るもの |
|---|---|
| `checks` | コミット前の検査（全ファイル）・`renv.lock` と `DESCRIPTION` の照合・lint・設定の読み込み（`configs/experiment/` を `repro_config_load()` で）・テスト・記録層の疎通と台帳 |
| `docker` | `make build` と同じイメージを作る。走らせるときに `docker` を選んだときだけ |

```bash
gh workflow run CI --ref <ブランチ>
gh workflow run CI --ref <ブランチ> -f docker=true
```

（[`gh workflow run`](https://cli.github.com/manual/gh_workflow_run)。走るのは GitHub にある `<ブランチ>` の中身なので、手元の変更は push してから）
