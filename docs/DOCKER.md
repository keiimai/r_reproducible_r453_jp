# 第1層 — Docker によるコンテナ構築

第1層は、同じ計算環境を立ち上げることだけを受け持つ（ホストに要るもの・入れないもの → [`SETUP.md`](SETUP.md) 0 節）。触る前に [`LAYERS.md`](LAYERS.md) を読む。

---

## 1. 構成

| ファイル | 役割 |
|---|---|
| `Dockerfile` | イメージの定義。renv までを入れた土台の段（`system`）・研究の apt を足す段（`bootstrap`）・依存を入れる段（`deps`）・本体の段（`dev`）でできている（Docker の [Dockerfile の説明書](https://docs.docker.com/reference/dockerfile/)） |
| `docker-compose.yml` | コンテナの起こし方（名前・マウント・ポート・環境変数・ネットワーク）。入口は `dev`・`task`・`lock` の 3 つ（→ 3 節。Docker の [Compose ファイルの説明書](https://docs.docker.com/reference/compose-file/)） |
| `.devcontainer/devcontainer.json` | VS Code から `dev` に入る設定（→ 3 節。[Dev Container の仕様](https://containers.dev/implementors/json_reference/)） |
| `.dockerignore` | イメージに入れるもの。すべてを外し（`*`）、ビルドに要るものだけを `!` で戻す（Docker の[ビルドの材料の説明](https://docs.docker.com/build/concepts/context/)）。末尾の見出しの下は、プロジェクトが行を足してよい（第4〜5層の余白。→ [`LAYERS.md`](LAYERS.md)） |
| `docker/p3m_repo.R` | 取得元を P3M の日付スナップショットにする（→ 2 節） |
| `docker/project_apt.txt` | プロジェクトが足す apt のパッケージ（第4〜5層の余白。書いてよいもの → [`LAYERS.md`](LAYERS.md)。仕組み → 2 節の層 6） |
| `docker/project_build.sh` | プロジェクトが足すビルドの手順（第4〜5層の余白。書いてよいもの → [`LAYERS.md`](LAYERS.md)。仕組み → 2 節の層 9） |
| `docker/project_env.txt` | プロジェクトがコンテナに渡す環境変数（第4〜5層の余白。書いてよいもの → [`LAYERS.md`](LAYERS.md)。仕組み → 3 節） |
| `docker/write_build_info.R` | ビルドの素性を書く（→ 2 節の層 11） |
| `docker/smoke_load.R` | ビルドの最後の検査（→ 2 節の層 12） |
| `.env.example` | `.env` の雛形（→ 3 節）。末尾の見出しの下は、プロジェクトが設定の名前を足してよい（第4〜5層の余白。→ [`LAYERS.md`](LAYERS.md)） |

CPU の種類は `PLATFORM` で変える。どこにも書かなければ `linux/arm64`（`Makefile` と `docker-compose.yml` の既定）。x64 の PC では、`.env` に `PLATFORM=linux/amd64` と書く（一度だけ変えるなら `make build PLATFORM=linux/amd64`。イメージは置き換わるので、その後の `make up`・`make check`・コミット前のフックにも同じ値が要る → 4 節）。`make` の `docker build`（`lock`・`build`）と compose の `platform:` の両方に効く。make の引数・ホストのシェルの変数・`.env`・既定の順に使う。

---

## 2. ビルドの流れ

`make build` が [`docker build`](https://docs.docker.com/reference/cli/docker/buildx/build/) を `--platform <CPU の種類>`（→ 1 節）と `--target dev` で叩き、ビルドの日時・コミット・名前（`docker-compose.yml` の `name:`）をビルド引数で渡して、`<名前>:dev` を作る。compose はこのイメージを作らず、取りにも行かない（[`pull_policy: never`](https://docs.docker.com/reference/compose-file/services/#pull_policy)）。`make lock` は `--target bootstrap` で `<名前>:bootstrap` を作り（依存を入れる前の段なので、`renv.lock` が壊れていても作り直せる）、compose の `lock` で `tools/make_lockfile.R` を走らせる（すること → [`WORKSPACE.md`](WORKSPACE.md) 2 節）。

共通ベース（`deps` の段までを入れたイメージ）があれば、`make build` は `bootstrap` をその上から始め（`RUNTIME_BASE`）、層 7 では共通ベースに無いパッケージだけを入れる。無ければ `system` から作る（入るパッケージの版は同じ）。

取得元は [P3M](https://packagemanager.posit.co/) の[日付スナップショット](https://docs.posit.co/rspm/user/get-repo-url.html#ui-frozen-urls)（`Dockerfile` の `ARG P3M_SNAPSHOT`）で、層 3・層 7・`make lock` が同じ `docker/p3m_repo.R` を使う。

| 層 | 段 | 中身 | 作り直される条件 |
|---|---|---|---|
| 1 | system | apt（[`curl`](https://packages.ubuntu.com/noble/curl)・[`libuv1-dev`](https://packages.ubuntu.com/noble/libuv1-dev)・[`libwebp-dev`](https://packages.ubuntu.com/noble/libwebp-dev)・日本語フォント [`fonts-noto-cjk`](https://packages.ubuntu.com/noble/fonts-noto-cjk)）。コンパイラと git はベースイメージ（[`rocker/rstudio:4.5.3`](https://rocker-project.org/images/versioned/rstudio.html)）にある | その行か、`BASE_IMAGE`・`P3M_SNAPSHOT` が変わったとき（テンプレートの取り込みなど。[`ARG` とキャッシュ](https://docs.docker.com/reference/dockerfile/#impact-on-build-caching)） |
| 2 | system | 環境変数。ロケール `C.UTF-8`・時間帯・スレッド数 1・renv の置き場所・[`R_LIBS`](https://search.r-project.org/R/refmans/base/html/libPaths.html)・`P3M_SNAPSHOT` | 同上 |
| 3 | system | `docker/p3m_repo.R` を `/opt` に置き、その日付の [renv](https://rstudio.github.io/renv/) を入れる | `p3m_repo.R` が変わったとき |
| 4 | system | renv の置き場所（`/opt/renv/library`・`/opt/renv/cache`）を作る | その行が変わったとき |
| 5 | system | 作業フォルダ `/app` と、ホームからのリンク（`/home/rstudio/app`） | 同上 |
| 6 | bootstrap | `docker/project_apt.txt` の apt（空なら何もしない） | そのファイルが変わったとき |
| 7 | deps | `renv.lock` の R の版・取得元の日付・renv の版をイメージと照らし（ずれたら止まる）、[`renv::restore()`](https://rstudio.github.io/renv/reference/restore.html) で `renv.lock` どおりに `/opt/renv/library` へ入れる | `renv.lock` が変わったとき |
| 8 | dev | RStudio Server の設定の既定。R のセッションを `/app` で始め、ペインの配置・テーマ・字・エディタの表示・保存の仕方を決める（Posit の[管理者向けの説明](https://docs.posit.co/ide/server-pro/admin/reference/session_user_settings.html)） | その行が変わったとき |
| 9 | dev | `docker/project_build.sh`（第4〜5層の余白。書いてよいもの → [`LAYERS.md`](LAYERS.md)）を `/opt` に置き、root の `sh -eu` で動かす（テンプレートでは何もしない）。命令が失敗するとビルドが止まり、通っても層 12 の検査に落ちれば止まる。層 10 より前に動くので、`/app` には層 7 で入れた `renv.lock` しか無く（`DESCRIPTION`・`R/` などは読めない）、ソースを変えても作り直されない | そのファイルが変わったとき |
| 10 | dev | `.dockerignore` が戻したものを `/app` に入れる（`COPY . .`） | それらが変わったとき |
| 11 | dev | ビルドの素性を `/opt/build-info.json` に書く（項目 → `docker/write_build_info.R`）。実行の記録がこれを取り込む | 毎回 |
| 12 | dev | 最後の検査（`rstudio` として `--vanilla`）。`DESCRIPTION` の依存と `renv.lock` のすべてのパッケージの読み込み（版は `DESCRIPTION` の依存だけ出す）・quarto の R エンジン（[`quarto check knitr`](https://quarto.org/docs/cli/check.html)）・RStudio Server を起動する `/init` と `rserver`・日本語フォント・`R/` の構文を確かめ、落ちたらビルドを止める | 毎回 |

P3M のコンパイル済みは、実行時に要るシステムの共有ライブラリを持ってこない（Posit の[コンパイル済みパッケージの説明](https://docs.posit.co/rspm/admin/serving-binaries.html#prerequisites)）。

層 1・層 6 の apt と、層 7 の renv は、ビルドの間だけ使うキャッシュ（[`RUN --mount=type=cache`](https://docs.docker.com/reference/dockerfile/#run---mounttypecache)）に、取ってきたものを置く。キャッシュの中身はイメージに入らず、次のビルドで使い回される（層が作り直されても、同じものは取り直さない）。このキャッシュは `make clean-docker` で消える。

起動すると、リポジトリが `/app` にマウントされ、イメージの中の `/app` は隠れる。`/opt/renv/library` は root の持ち物で、コンテナの中からは依存を足せない（足し方 → [`LAYERS.md`](LAYERS.md) の余白「パッケージ」。版を決めるもの → [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 5 節）。

ビルドのログ（層 11）の `vcs_ref` が `unknown` なら、git 化していないか、`make build` を通していない。末尾に `-dirty` が付いていれば、追跡しているファイルに未コミットの変更がある状態で作った（`make lock` のあと、コミットの前に `make build` すると、そうなる）。

---

## 3. 起動と環境変数

| 入口 | 中身 |
|---|---|
| `make up` | RStudio Server を起動し、開ける URL を 1 行出す。ポートは `127.0.0.1` の 8787〜8886 から Docker が選び（起動のたびに変わる。[`ports`](https://docs.docker.com/reference/compose-file/services/#ports)）、認証は無い（`DISABLE_AUTH=true`。この PC の中からしか届かない） |
| Dev Container | VS Code が `dev` のコンテナに入る（RStudio Server は立ち上げない。開き方 → [`SETUP.md`](SETUP.md) 2-B）。R の言語サーバーとセッションの連携、VS Code の git は切ってある |
| `make shell`・`make check` など・コミット前のフック | 使い捨てのコンテナ（compose の `task`）で動く（→ [`WORKSPACE.md`](WORKSPACE.md) 2 節） |
| `make lock` | `renv.lock` を作り直す（→ 2 節）。取ってきたパッケージは Docker のボリューム `renv-cache` に残す（`make lock` が [`docker compose run -v`](https://docs.docker.com/reference/cli/docker/compose/run/) で付ける。名前は固定で、このテンプレートから起こした全プロジェクトで共有する。消すなら [`docker volume rm renv-cache`](https://docs.docker.com/reference/cli/docker/volume/rm/)） |

どの入口も、Docker の既定のネットワーク `bridge` につなぐ（[`network_mode: bridge`](https://docs.docker.com/reference/compose-file/services/#network_mode)）。

コンテナまわりの設定は、次の 2 つのファイルに書く。

| ファイル | Git | 読むもの | 書くもの |
|---|---|---|---|
| `.env` | 追跡しない（PC ごとに持つ） | `make` と compose（`${...}` の展開）。プロジェクトのコードも読む（→ [`LAYERS.md`](LAYERS.md)） | 既定から変える設定（CPU の種類 `PLATFORM`・スレッドの数・時刻帯 `CONTAINER_TZ`）と、秘密の値 |
| `docker/project_env.txt`（第4〜5層の余白） | 追跡する（全員で同じ） | コンテナ（`dev` と `task` が [`env_file:`](https://docs.docker.com/reference/compose-file/services/#env_file) で読む） | コンテナの中で使う、秘密でない環境変数（→ [`LAYERS.md`](LAYERS.md)） |

`.env` は無くてよい（`make env` で雛形を写し、変えたい行の頭の `#` を外す）。`.env` の値がコンテナに届くのは、`environment:` に並べた次の変数だけである。ホストのシェルに同じ名前の変数があれば、`.env` より先に使われる（Compose の[変数の展開の説明](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)）。`COMPOSE_` で始まる変数は書かない（Compose の[あらかじめ決まった変数](https://docs.docker.com/compose/how-tos/environment-variables/envvars/)。名前は `make rename` で変える）。

| 変数 | 既定 | 中身 |
|---|---|---|
| [`OMP_`](https://gcc.gnu.org/onlinedocs/libgomp/OMP_005fNUM_005fTHREADS.html)・[`OPENBLAS_`](https://www.openmathlib.org/OpenBLAS/docs/runtime_variables/)・[`MKL_NUM_THREADS`](https://www.intel.com/content/www/us/en/docs/onemkl/developer-guide-linux/current/onemkl-specific-env-vars-for-openmp-thread-ctrl.html) | `1` | 数値計算のスレッド数（再現との関わり → [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 4 節） |
| `TZ`（`.env` では `CONTAINER_TZ`） | `Asia/Tokyo` | コンテナの時刻帯（[tz データベース](https://www.iana.org/time-zones)の名前。例: `Europe/London`。実行 ID と記録の時刻 → [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 2 節） |

`docker/project_env.txt` は、`make` と compose の `${...}` が読まない。そのため、CPU の種類はここでは変えられない。`environment:` に並べた名前（`DISABLE_AUTH`・スレッドの数・`TZ`）は、ここに書いても変わらず（Compose の[優先の順](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/)）、`Dockerfile` の `ENV`（層 2 の `LANG`・`R_LIBS` など）は、書くと変わってしまう（書かないもの → [`LAYERS.md`](LAYERS.md)「第4〜5層の『余白』」）。

---

## 4. 困ったとき

| 表示 | 原因 | 対処 |
|---|---|---|
| `No such image: <名前>:dev` | イメージを作っていない（→ 2 節）。名前が `name:` と違えば、`.env` の `COMPOSE_PROJECT_NAME` | `make build`（`.env` が原因なら、その行を消す） |
| `does not provide the specified platform` | イメージの CPU の種類と、今の `PLATFORM` が違う（`make build PLATFORM=…` で一度だけ変えたときなど） | `.env` の `PLATFORM` をイメージと同じにするか、今の `PLATFORM` で `make build` し直す |
| `renv.lock は R … 用ですが、イメージの R は … です` | テンプレートの取り込みで `BASE_IMAGE` が変わり、まだ `make lock` をしていない | `make lock` → `make build` |
| `renv.lock の取得元（…）に P3M_SNAPSHOT=… が含まれません` | 取り込みで `P3M_SNAPSHOT` が変わり、まだ `make lock` をしていない | 同上 |
| `renv.lock は renv … で作られていますが、イメージの renv は … です` | 取り込みでイメージの renv の版が変わり、まだ `make lock` をしていない（`renv.lock` を作った renv と版が違う） | 同上 |
| `renv.lock に renv 自身が載っていません` | `renv.lock` の `Packages` に renv が無い（`make lock` を使わずに作ったか、手で書き換えた） | 同上 |
| `ビルド検査に失敗しました:` の下に `読み込めません` と `cannot open shared object file`（`make lock` では `入りましたが読み込めないパッケージがあります`） | システムの共有ライブラリが足りない | その `.so` を含む `-dev` のパッケージを Ubuntu の[パッケージの中身の検索](https://packages.ubuntu.com/#search_contents)で探して `docker/project_apt.txt` に足し、`make lock` → `make build` |
| `ビルド検査に失敗しました:` の下に、それ以外の `読み込めません` | `renv.lock` と `DESCRIPTION` がずれている | `make lock` → `make build` |
| `ビルド検査に失敗しました:` の下に `quarto: knitr エンジンに要る … が読み込めません` | knitr か rmarkdown が入っていない（`DESCRIPTION` から外したか、`renv.lock` とずれている） | `DESCRIPTION` に knitr と rmarkdown があるかを確かめ、`make lock` → `make build` |
| `ビルド検査に失敗しました:` の下に `quarto: knitr エンジンが動きません`（その下に `quarto check knitr` の最後の 3 行） | quarto が R の knitr を動かせない。理由は、その 3 行に出る | 3 行を読む。knitr か rmarkdown が理由なら、上の行と同じ。それ以外は、テンプレートに依頼する |
| `ビルド検査に失敗しました:` の下に `…: 実行権がありません` | `/init` か `rserver` はあるが、`rstudio` が実行できない（層 9 の `docker/project_build.sh` が持ち物か権限を変えた） | `docker/project_build.sh` を確かめる |
| `ビルド検査に失敗しました:` の下に `R/…: 構文エラー` | `R/` のファイルに、R として読めない所がある（後ろに場所が出る） | そのファイルを直して `make build` |
| `make up` で `No password has been supplied` と `chpasswd ... failed` | 正常（認証を無効にしてあるので、パスワードを設定しない） | 何もしない |
| `failed to resolve source metadata for docker.io/docker/dockerfile:…` | `Dockerfile` の 1 行目（[`# syntax=`](https://docs.docker.com/reference/dockerfile/#syntax)）が指す、Dockerfile を読む部品を Docker Hub に問い合わせる途中で、通信が切れた（この問い合わせは、前に作った結果がすべて手元にあっても、作るたびに入る） | 通信を確かめて、同じ命令をもう一度叩く（前に作った結果はそのまま使われる） |
| `no space left on device` | Docker の仮想ディスクが埋まった | [`docker system df`](https://docs.docker.com/reference/cli/docker/system/df/) で見て、`make clean-docker` |
| `ports are not available` | Docker が選んだ番号を、別のプロセスが使っている | [`lsof -nP -iTCP:<番号> -sTCP:LISTEN`](https://github.com/lsof-org/lsof) で探して止める |
