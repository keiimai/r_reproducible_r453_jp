# --- よく使うコマンド（make help で一覧）（WORKSPACE.md 2 節）---

# --- make だけで一覧を出す（WORKSPACE.md 2 節）---
.DEFAULT_GOAL := help

# --- コンテナの中かどうかを見分ける（WORKSPACE.md 2 節）---
ifneq ($(wildcard /opt/build-info.json),)
IN_CONTAINER := 1
endif

# --- Docker を叩く target、git を使う target、コンテナの中で走る target の一覧（WORKSPACE.md 2 節）---
DOCKER_TARGETS    := lock build base up down shell clean-docker
GIT_TARGETS       := hooks hooks-all
CONTAINER_TARGETS := smoke lock-check lint test check verify runs render

# --- 同じ名前のファイルがあっても target を走らせる（WORKSPACE.md 2 節）---
.PHONY: help env rename $(GIT_TARGETS) $(DOCKER_TARGETS) $(CONTAINER_TARGETS)

# --- ホストとコンテナのどちらでも動く（WORKSPACE.md 2 節）---

# --- target の一覧を出す（WORKSPACE.md 2 節）---
help:  ## この一覧を表示
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- .env を雛形から作る（WORKSPACE.md 2 節）---
env:  ## .env を雛形から作る（任意。既定から変えたいときだけ。既にあれば何もしない）
	@test -f .env && echo ".env は既にあります。" || { \
		cp .env.example .env; \
		echo ".env を作成しました。変えたい行の頭の # を外して、値を書き換えてください。"; }

# --- テンプレートからプロジェクトを起こす（SETUP.md 手順 3・WORKSPACE.md 2 節）---
rename:  ## Docker の名前の頭にプロジェクトの名前を付ける（例: make rename NAME=myproject）
	@test -n "$(NAME)" || { echo "使い方: make rename NAME=<プロジェクトの名前>"; exit 1; }
	@echo "$(NAME)" | grep -Eq '^[a-z][a-z0-9]+$$' || { \
		echo "エラー: NAME は小文字の英字で始まる、2 文字以上の小文字英数字にしてください。"; \
		echo "Docker の名前（イメージ・コンテナ）に使うので、大文字・.・_・- は使えません。"; exit 1; }
	@grep -Eq '^name: [a-z0-9]+$$' docker-compose.yml || { \
		echo "既に改名済みのようです（docker-compose.yml の name: に - が入っています）。"; exit 1; }
	sed -i.rename-bak -e 's/^name: \(.*\)$$/name: $(NAME)-\1/' docker-compose.yml
	rm -f docker-compose.yml.rename-bak
	@echo "改名しました: Docker の名前は $$(sed -n 's/^name: //p' docker-compose.yml) です"
	@echo "次に: 新しいプロジェクトなら、docs/SETUP.md 手順 3 のとおりコミットする。"
	@echo "      テンプレートの更新を取り込んでいる途中なら、コミットは docs/LAYERS.md の取り込みの手順でまとめて行う。"

ifdef IN_CONTAINER
# --- コンテナの中だけで動く（WORKSPACE.md 2 節）---

# --- Docker を叩く target は、ホストで打つよう案内して止める（WORKSPACE.md 2 節）---
$(DOCKER_TARGETS):
	@echo "$@ はホスト（PC のターミナル）で実行してください。コンテナの中に Docker はありません。"
	@exit 1

# --- git を使う target は、ホストで打つよう案内して止める（WORKSPACE.md 3 節）---
$(GIT_TARGETS):
	@echo "$@ はホスト（PC のターミナル）で実行してください。コンテナの中では git を使いません。"
	@exit 1

# --- 記録層の経路を 1 回通す（REPRODUCIBILITY.md 2 節）---
smoke:  ## 記録層の経路を 1 回通す（run_id の発行 → 入力の記録 → 成果物 → 台帳）
	Rscript -e 'source("R/repro.R"); repro_smoke()'

# --- renv.lock が DESCRIPTION と食い違っていないかを確かめる（WORKSPACE.md 2 節）---
lock-check:  ## renv.lock が DESCRIPTION と食い違っていないか検査（CI と同じ）
	Rscript --vanilla tools/make_lockfile.R --check

# --- 静的検査（WORKSPACE.md 2 節）---
lint:  ## lintr で静的検査（1 件でもあれば失敗）
	Rscript -e "lints <- structure(c(lintr::lint_package(), lintr::lint_dir('tools'), lintr::lint_dir('docker'), lintr::lint_dir('notebooks')), class = 'lints'); print(lints); if (length(lints) > 0) quit(status = 1)"

# --- テスト（WORKSPACE.md 2 節）---
test:  ## テストを実行
	Rscript -e "testthat::test_dir('tests/testthat', reporter = 'summary', stop_on_failure = TRUE)"

# --- lock の検査・lint・テスト（WORKSPACE.md 2 節）---
check: lock-check lint test  ## lock の検査 + lint + テスト

# --- check と記録層の疎通確認（WORKSPACE.md 2 節）---
verify: check smoke  ## check に記録層の疎通確認まで加えた完全版

# --- 実行台帳を作り直して表示する（REPRODUCIBILITY.md 3 節）---
runs:  ## 実行台帳を作り直して表示（例: make runs EXP=smoke LIMIT=10）
	Rscript -e 'source("R/repro.R"); repro_runs(experiment = "$(EXP)", limit = "$(LIMIT)", show = TRUE)'

# --- 描画（REPRODUCIBILITY.md 2 節）---
render:  ## Quarto 文書を描画して outputs/reports/<run_id>/ に出す（例: make render QMD=notebooks/<名前>.qmd P="n:10"）
	@test -n "$(QMD)" || { echo "使い方: make render QMD=notebooks/<名前>.qmd [P=\"名前:値 …\"]"; exit 1; }
	@test -f "$(QMD)" || { echo "$(QMD) がありません（パスはリポジトリの根から書く）。"; exit 1; }
	@name="$$(basename "$(QMD)")"; \
	run_id="$$(Rscript -e 'source("R/repro.R"); cat(.repro_new_run_id(commandArgs(TRUE)[1], repro_settings()$$repro_dir))' "$${name%.*}")" || exit 1; \
	work="$$(dirname "$(QMD)")/.quarto"; { [ -d "$$work" ] && [ ! -L "$$work" ]; } || ln -sfn "$$(mktemp -d)" "$$work" 2>/dev/null || true; \
	out="$$(mktemp -d)"; \
	REPRO_RUN_ID="$$run_id" quarto render "$(QMD)" --output-dir "$$out" $(foreach p,$(P),-P $(p)) || { \
	Rscript -e 'source("R/repro.R"); .repro_mark_failed(commandArgs(TRUE)[1])' "$$run_id"; exit 1; }; \
	mkdir -p "outputs/reports/$$run_id" && cp -R "$$out"/. "outputs/reports/$$run_id/" && \
	echo "描画しました: outputs/reports/$$run_id/"

else
# --- ホストだけで動く（WORKSPACE.md 2 節）---

# --- コンテナの中で走る target は、コンテナに入り直す（WORKSPACE.md 2 節）---
$(CONTAINER_TARGETS):
	@docker compose run --rm --user rstudio task make $@ $(MAKEOVERRIDES)

# --- コミット前の検査を有効にする（WORKSPACE.md 3 節）---
hooks:  ## git のコミット前フックを有効にする（コミットはホストで行う）
	@test -d .git || { echo "git リポジトリではありません。先に git init を実行してください（docs/SETUP.md 手順 2）。"; exit 1; }
	chmod +x .githooks/pre-commit
	git config --local core.hooksPath .githooks
	git config --local hook.precommit-checks.command .githooks/pre-commit
	git config --local --replace-all hook.precommit-checks.event pre-merge-commit
	@echo "有効にしました: .githooks/pre-commit（git 2.54 以降なら、マージのコミットにも同じ検査をかける）"
	@echo "追跡中の全ファイルに一括適用するには: make hooks-all"

# --- コミット前の検査を全ファイルにかける（WORKSPACE.md 3 節）---
hooks-all:  ## 追跡中の全ファイルにコミット前の検査をかける
	bash .githooks/pre-commit --all

# --- イメージに渡すビルドの日時・コミット（作業ツリーが汚れていれば -dirty を付ける）・名前（DOCKER.md 2 節）---
BUILD_DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
VCS_REF    := $(shell git describe --always --dirty --abbrev=40 --exclude='*' 2>/dev/null || echo unknown)
IMAGE      := $(shell sed -n 's/^name: //p' docker-compose.yml)

# --- CPU の種類（make の引数・.env の PLATFORM=・既定の linux/arm64 の順。compose にも渡す）（DOCKER.md 1 節）---
PLATFORM := $(or $(PLATFORM),$(shell sed -n 's/^PLATFORM=//p' .env 2>/dev/null | tail -n 1 | tr -d "\"' \r"),linux/arm64)
export PLATFORM

# --- 共通ベースの名前（テンプレートの名前・手で上げる番号・CPU の種類・Dockerfile の deps までと p3m_repo.R の検査値）（DOCKER.md 2 節）---
BASE_LABEL := 2
BASE_TAG   := $(shell echo $(IMAGE) | sed 's/^[a-z][a-z0-9]*-\(r[0-9]\)/\1/')-base:$(BASE_LABEL)-$(subst /,-,$(patsubst linux/%,%,$(PLATFORM)))-$(shell sed '/^FROM deps AS dev/,$$d' Dockerfile | cat - docker/p3m_repo.R | cksum | cut -d' ' -f1)

# --- 名前がテンプレートのままなら注意を出す（WORKSPACE.md 2 節）---
CHECK_NAME = grep -Eq '^name: [a-z0-9]+$$' docker-compose.yml \
	&& echo "注意: Docker の名前がテンプレートのままです（make rename → docs/SETUP.md 手順 3）。" \
	&& echo "      このままだと、同じ名前のイメージとコンテナをほかのプロジェクトと取り合います。" || true

# --- コミット前のフックが無効なら注意を出す（WORKSPACE.md 3 節）---
CHECK_HOOKS = test -e .git \
	&& test "$$(git config --get core.hooksPath)" != ".githooks" \
	&& echo "注意: コミット前のフックが有効になっていません（make hooks → docs/SETUP.md 手順 6）。" \
	&& echo "      このままだと、コミットしても data/ 配下や秘密鍵などの検査が走りません。" || true

# --- renv.lock を作り直す（取ってきたパッケージは、全プロジェクトで共有するボリューム renv-cache に残す）（DOCKER.md 3 節）---
lock:  ## renv.lock を作り直す（DESCRIPTION を変えたら実行）
	docker build --platform $(PLATFORM) --target bootstrap -t $(IMAGE):bootstrap .
	docker compose run --rm --user rstudio -v renv-cache:/opt/renv/cache lock Rscript --vanilla tools/make_lockfile.R

# --- イメージを作る（DOCKER.md 2 節）---
build:  ## renv.lock からイメージを作る
	@$(CHECK_NAME)
	@$(CHECK_HOOKS)
	docker build --platform $(PLATFORM) --target dev --build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(VCS_REF) --build-arg IMAGE_NAME=$(IMAGE) -t $(IMAGE):dev \
		$$(docker image inspect -f '--build-arg RUNTIME_BASE=$(BASE_TAG) --build-arg RUNTIME_BASE_ID={{.Id}}' $(BASE_TAG) 2>/dev/null) .

# --- 共通ベースを作る（テンプレートのフォルダでだけ。同じ名前は作り直さない）（DOCKER.md 2 節）---
base:  ## 共通ベースを作る（テンプレートのフォルダでだけ。あれば make build がその上に作る）
	@grep -Eq '^name: [a-z0-9]+$$' docker-compose.yml && ! grep -q '^Config/Needs/project:' DESCRIPTION \
		&& ! sed -e 's/#.*//' docker/project_apt.txt | grep -q '[^[:space:]]' \
		|| { echo "共通ベースはテンプレートのフォルダで作ります（研究の依存を混ぜないため）。"; exit 1; }
	@! docker image inspect $(BASE_TAG) >/dev/null 2>&1 \
		|| { echo "$(BASE_TAG) はもうあります（作り直さない。材料を変えたら BASE_LABEL を上げる）。"; exit 1; }
	docker build --platform $(PLATFORM) --target deps -t $(BASE_TAG) .

# --- RStudio Server を起動し、開ける URL を出す（WORKSPACE.md 2 節）---
up:  ## RStudio Server を起動（開ける URL を 1 行出す。番号は起動のたびに変わる。Ctrl-C で停止）
	@$(CHECK_NAME)
	@$(CHECK_HOOKS)
	@for i in $$(seq 1 60); do \
		sleep 1; \
		port="$$(docker compose port dev 8787 2>/dev/null)"; \
		[ -n "$$port" ] || continue; \
		curl -fs --max-time 2 -o /dev/null "http://$$port/" || continue; \
		printf '\n\033[36m[up] RStudio が開けます: http://localhost:%s\033[0m\n\n' "$${port##*:}"; \
		break; \
	done &
	docker compose up

# --- コンテナを止めて片付ける（WORKSPACE.md 2 節）---
down:  ## コンテナ（make render などの使い捨てのものも）を停止して片付ける
	docker compose --profile tools down --remove-orphans

# --- コンテナの中で bash を開く（WORKSPACE.md 2 節）---
shell:  ## コンテナ内で bash を開く
	docker compose run --rm --user rstudio task bash

# --- Docker の片付け（WORKSPACE.md 2 節）---
clean-docker:  ## Docker の宙ぶらりんイメージとビルドキャッシュを削除（この PC の全プロジェクトに及ぶ。確認あり）
	@docker system df
	@echo ""
	@echo "宙ぶらりんのイメージとビルドキャッシュを削除します。"
	@echo "★このプロジェクトだけでなく、この PC の Docker 全体が対象です。"
	@echo "  残るもの : 使用中のイメージ（$$(docker compose config --images | head -n 1)）とほかのタグの付いたイメージ・data/・outputs/"
	@echo "  消えるもの: タグの無い古いイメージ・すべてのプロジェクトのビルドキャッシュ"
	@echo "             （部品のダウンロード用のキャッシュも含む。次の make build・make lock は"
	@echo "              どのプロジェクトでも作り直しから始まり、遅くなる）"
	@echo "よろしければ Enter、中止は Ctrl-C。"
	@read -r _
	docker image prune -f
	docker builder prune -f
	@echo ""
	@docker system df

endif

# --- プロジェクトが足す命令（第4〜5層。無ければ何もしない。テンプレートの命令と同じ名前なら止める）（WORKSPACE.md 2 節）---
PROJECT_MK_CLASH := $(filter help env rename $(GIT_TARGETS) $(DOCKER_TARGETS) $(CONTAINER_TARGETS),$(shell sed -nE 's/^([A-Za-z0-9_-]+)[[:space:]]*:([^=]|$$).*/\1/p' project.mk 2>/dev/null))
$(if $(PROJECT_MK_CLASH),$(error project.mk の $(PROJECT_MK_CLASH) は、テンプレートの命令と同じ名前です。名前を変えてください（WORKSPACE.md 2 節）))
-include project.mk
