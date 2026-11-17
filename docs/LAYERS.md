# 5 層構成 — どのファイルがどの層か

| 層 | 中身 | 配布先のプロジェクトで | 仕様書 |
|---|---|---|---|
| **1** | Docker によるコンテナ構築 | **修正しない**（余白 5 つを除く。→ 下の「第4〜5層の『余白』」） | [`DOCKER.md`](DOCKER.md) |
| **2** | 開発環境（ディレクトリ・Makefile・検査・CI） | **修正しない**（余白 2 つを除く。→ 下の「第4〜5層の『余白』」） | [`WORKSPACE.md`](WORKSPACE.md) |
| **3** | 再現性の記録（依存の固定・記録層） | **修正しない**（余白 3 つを除く。→ 下の「第4〜5層の『余白』」） | [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) |
| **4** | 解析の部品（入口から呼ぶ関数）と、そのテスト | **プロジェクトが書く**（テンプレートには無い。→ 下の「ファイルを足してよい場所」） | — |
| **5** | 解析の実行（入口・設定・その研究の文書） | **プロジェクトが書く**（`README.md`・`CITATION.cff`・`CHANGELOG.md` だけは、テンプレートの雛形を書き換える） | — |

手順書（どの層にも属さない、横断的な立ち上げ方）は [`SETUP.md`](SETUP.md)。

---

## どのファイルがどの層か

```
  第5層  解析の実行
    │  （入口・設定・その研究の文書。notebooks / configs / docs / .github/workflows /
    │    README.md / CITATION.cff / CHANGELOG.md / LICENSE-docs）
    ▼
  第4層  解析の部品
    │  （入口から呼ぶ関数とそのテスト。R/project_*.R / tests/testthat の test-project_*.R・helper-project*.R）
    ▼
  第3層  再現性の記録
    │  （R/repro.R / DESCRIPTION / renv.lock（余白に合わせて作り直す） / .Rprofile /
    │    tests/testthat の test-repro.R・helper-load.R / notebooks の README.md・_metadata.yml・_project_author.yml・styles.css）
    ▼
  第2層  開発環境
    │  （Makefile / project.mk / .gitignore / コミット前フックと tools/ / CI / .editorconfig / .lintr / .vscode/settings.json / ディレクトリ骨格と setup.R /
    │    data/ の README.md / LICENSE）
    ▼
  第1層  Docker によるコンテナ構築
       （Dockerfile / compose / devcontainer / docker/ / .dockerignore / .env.example）
```

---

## 第4〜5層の「余白」

第1〜3層のファイルの中で、**プロジェクトが書き込んでよい場所は 10 個だけである。** 書いてよい範囲の定義は次の表だけにある。例は範囲を狭めない。

| 余白 | 場所 | 目的（書いてよい範囲） | 例 | 書かないもの |
|---|---|---|---|---|
| **パッケージ** | `DESCRIPTION` の [`Config/Needs/project:`](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#The-DESCRIPTION-file)（と `renv.lock`） | 第4〜5層が使う R のパッケージのうち、`Imports`・`Suggests` に無いもの | その研究でだけ使う推定や図のパッケージ | `Imports`・`Suggests` への追記。CRAN（[P3M](https://packagemanager.posit.co/) のスナップショット）に無い名前 |
| **システムパッケージ** | `docker/project_apt.txt` | 第4〜5層を動かすのに要る apt のパッケージ | 依存の読み込みに要るもの（`-dev` の側）、第4〜5層が動かすプログラム（仮想ディスプレイなど） | R のパッケージ（`DESCRIPTION` に書く） |
| **ビルドの手順** | `docker/project_build.sh` | R のパッケージ（`DESCRIPTION`）・apt のパッケージ（`docker/project_apt.txt`）・イメージに入れるファイル（`.dockerignore`）のどれでもできない、イメージを作る途中の命令 | 入れたソフトの設定を書き換える | `DESCRIPTION`・`docker/project_apt.txt`・`.dockerignore` でできること |
| **Git に載せないもの** | `.gitignore` の末尾の見出しの下 | 第4層・第5層が作る、Git で追跡しないファイルの行 | — | テンプレートの行の削除（秘密情報・データ本体・成果物などを外している） |
| **make の命令** | 根の `project.mk` の見出しの下 | 第4〜5層が使う `make` の命令 | 決まった手順をまとめて動かす命令 | テンプレートの命令と同じ名前の命令 |
| **イメージに入れるもの** | `.dockerignore` の末尾の見出しの下 | イメージに入れる第4層のファイルを戻す `!<パス>` の行 | — | テンプレートの行の削除 |
| **設定の名前** | `.env.example` の末尾の見出しの下 | 第4層・第5層のコードが `.env` から読む設定の名前 | `API_TOKEN=`（値は空にする） | 値（`.env` に書く） |
| **コンテナの環境変数** | `docker/project_env.txt` | 第4〜5層の都合でコンテナの中に要る、秘密でない環境変数（第1〜3層のコードが読むものでもよい） | 第4〜5層が動かすプログラムの設定 | 秘密の値（`.env` に書く）。`docker-compose.yml` の `environment:` の名前（上書きできない）。`Dockerfile` の `ENV` の名前。`REPRO_RUN_ID`（`make render` が描画ごとに渡す実行 ID） |
| **レポートの著者** | `notebooks/_project_author.yml` | 第5層のノートブックが、レポートに出す著者と所属 | — | — |
| **R の起動時の処理** | `.Rprofile` の末尾の見出しの下 | R の起動時に動かす、第4〜5層の短い処理 | — | 時間のかかる処理。パッケージの読み込み。秘密の値 |

余白ごとの書き方と、変えた後の操作は次のとおりである。

| 余白 | 書き方と、変えた後の操作 |
|---|---|
| **パッケージ** | `Suggests` と同じ書き方で、`DESCRIPTION` の末尾に置く。足したら `make lock && make build` |
| **システムパッケージ** | 1 行に 1 つ。足したら `make lock && make build`（→ [`DOCKER.md`](DOCKER.md) 4 節） |
| **ビルドの手順** | 足したら `make build`（動き方 → [`DOCKER.md`](DOCKER.md) 2 節の層 9） |
| **make の命令** | `##` を付けた命令は `make help` に出る。命令の行の字下げはタブにする |
| **イメージに入れるもの** | イメージの中のファイルを読むのは、ビルドの間（[`DOCKER.md`](DOCKER.md) 2 節の層 11・12）だけである。足したら `make build` |
| **設定の名前** | `.env` はコンテナに環境変数として届かないので（→ [`DOCKER.md`](DOCKER.md) 3 節）、コードが `.env` を読む（[`readRenviron(".env")`](https://search.r-project.org/R/refmans/base/html/readRenviron.html)） |
| **コンテナの環境変数** | `#` で始まる行は読まない。変えたらコンテナを起こし直す（仕組み → [`DOCKER.md`](DOCKER.md) 3 節） |
| **レポートの著者** | 共著者は `- name:` を足し、所属が複数なら `affiliation:` の下に並べる（Quarto の[著者と所属](https://quarto.org/docs/authoring/front-matter.html#authors-and-affiliations)） |
| **R の起動時の処理** | 書くときの注意は [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 1 節 |

**第4〜5層に要るものが、どの余白の目的にも当てはまらないときは、第1〜3層を書き換えず、近い余白に無理に入れず、テンプレートに依頼する**（余白の目的を広げるか、新しい余白を作る）。

---

## 派生プロジェクトとの関係

**第1〜3層は、テンプレートとバイト一致に保つ。** 差が出てよいのは、名前（`docker-compose.yml` の `name:`）と余白、`renv.lock`（余白を含む `DESCRIPTION` から `make lock` で作り直す。手で書き換えない）、第4〜5層のファイル（テンプレートに無いものすべて）、`data/` のデータ、`docs/definition/`、`README.md`・`CITATION.cff`・`CHANGELOG.md` だけである。

### ファイルを足してよい場所

第4層・第5層はファイルを足して書く。置く場所は上の図のとおりで、入口は `notebooks/` の直下のノートブックで（描き方 → [`notebooks/README.md`](../notebooks/README.md)。プロジェクトが `.R` を置くのは `R/` と `tests/testthat/` だけ）、実験の設定は `configs/experiment/` に置く（CI が読む → [`WORKSPACE.md`](WORKSPACE.md) 4 節）。`R/` の直下の `.R`・`.r` は R のパッケージにせず、使う側（テストの `helper-load.R` とノートブック）が [`source()`](https://search.r-project.org/R/refmans/base/html/source.html) で読む。`R/` の関数では `library()` を使わず、`dplyr::filter()` のように `パッケージ::関数` で呼ぶ。記録層の関数は `repro_` で始まり、研究側の関数にはこの名前を付けない。`docs/` には、テンプレートの文書と同じ名前のファイルを置かない。`docs/definition/` には、人が読む変数定義を置く（コードからは読まない）。

### テンプレートの更新を取り込む

テンプレートのリポジトリに push 済みの 1 つのコミットを単位にして、第1〜3層をまとめて取り込む（層ごとに版が違うと、エラーも出ずに食い違う）。ホスト（PC のターミナル）で、プロジェクトの作業ツリーをコミット済みにしてから行う。`<テンプレート>` はテンプレートの手元の clone、`<前回>` はプロジェクトの `CHANGELOG.md` の冒頭の欄にあるコミット、`<今回>` は取り込むコミットである。

1. `docker-compose.yml` の `name:` の行を、`<前回>` のテンプレートと同じ値に書き戻す。今のテンプレートでは `name: r453` である。
2. テンプレートの差分を当てる（[`git apply`](https://git-scm.com/docs/git-apply)）。中身がプロジェクトのものになる `README.md`・`CHANGELOG.md`・`CITATION.cff`・`renv.lock` は外す。

   ```bash
   git -C <テンプレート> diff --binary <前回> <今回> -- . ':!README.md' ':!CHANGELOG.md' ':!CITATION.cff' ':!renv.lock' | git apply --reject
   ```

   当たらなかった部分は `<ファイル>.rej` に残る（余白のファイルにだけ出るはず）。テンプレートの中身を写してからプロジェクトの行を戻し、`.rej` を消す。最後に [`git add -A`](https://git-scm.com/docs/git-add) する（テンプレートが消したファイルを、索引からも消す）。
3. テンプレートと比べる（[`git archive`](https://git-scm.com/docs/git-archive)）。出てよいのは、上の「差が出てよい」ファイルだけである。

   ```bash
   git -C <テンプレート> archive <今回> | tar -x -C <空のフォルダ>
   diff -rq -x .git <空のフォルダ> . | grep -v '^Only in \.[:/]'
   ```

4. `make rename NAME=<名前>` で、名前を付け直す。
5. テンプレートのフォルダにある `docs/TEMPLATE_CHANGELOG.md`（Git では追跡しない、運用者の手元だけの記録）のうち、取り込んだ範囲の項にある「派生での作業」を行う。テンプレートの `DESCRIPTION` か `renv.lock` が変わっていれば、`make lock` も行う。派生での作業の `make hooks-all` と手順 6 のフックが、イメージが無いか CPU の種類が違うと止まったら、（`make lock` をするならその後に）`make build` してから行う（→ [`WORKSPACE.md`](WORKSPACE.md) 3 節）。
6. `CHANGELOG.md` の冒頭の欄を `<今回>` に書き換え、`[Unreleased]` に取り込みの項（見出しは `### 変更（テンプレートの取り込み: <前回> → <今回>）`。中身は派生での作業と、結果が変わるか（値が変わる／バイトだけ変わる／変わらない。`TEMPLATE_CHANGELOG.md` の項に書いてあるものを写す））を足し、`git add -A` して、ここまでを 1 つのコミットにする。
7. `make build` と `make verify`。通らなければ直して、コミットを足す。

main に戻さないブランチを持つプロジェクトは、main で取り込んでから、各ブランチに main をマージする（[`git merge main`](https://git-scm.com/docs/git-merge)。rebase と強制 push はしない）。依存は main でまとめて宣言し、全ブランチで同じ `renv.lock` にする。
