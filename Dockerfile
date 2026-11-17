# syntax=docker/dockerfile:1.27.0

# --- イメージの定義（R 4.5.3 / renv / CPU のみ / linux/arm64）（DOCKER.md 2 節）---
ARG BASE_IMAGE=rocker/rstudio:4.5.3
ARG P3M_SNAPSHOT=2026-04-01

# --- 研究のイメージの土台（共通ベースがあれば make build がその名前を渡す）（DOCKER.md 2 節）---
ARG RUNTIME_BASE=system

# --- ステージ1: renv までを入れた土台（DOCKER.md 2 節）---
FROM ${BASE_IMAGE} AS system
ARG P3M_SNAPSHOT

# --- 層1: システムパッケージ（DOCKER.md 2 節）---
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update && apt-get install -y --no-install-recommends \
        curl \
        libuv1-dev \
        libwebp-dev \
        fonts-noto-cjk

# --- 層2: 実行環境の固定（DOCKER.md 2 節）---
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Tokyo \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    RENV_PATHS_CACHE=/opt/renv/cache \
    RENV_PATHS_LIBRARY=/opt/renv/library \
    R_LIBS_USER=/opt/renv/library \
    R_LIBS=/opt/renv/library:/usr/local/lib/R/site-library:/usr/local/lib/R/library \
    P3M_SNAPSHOT=${P3M_SNAPSHOT}

# --- 層3: renv 本体（DOCKER.md 2 節）---
COPY --chmod=644 docker/p3m_repo.R /opt/p3m_repo.R
RUN R -q -e "source('/opt/p3m_repo.R'); \
             cat('[p3m]', use_p3m(Sys.getenv('P3M_SNAPSHOT')), '\n'); \
             install.packages('renv'); \
             cat('renv', as.character(packageVersion('renv')), '\n')"

# --- 層4: renv の置き場所（DOCKER.md 2 節）---
RUN mkdir -p /opt/renv/library /opt/renv/cache \
    && chown -R rstudio:rstudio /opt/renv

# --- 層5: 作業ディレクトリ（DOCKER.md 2 節）---
WORKDIR /app
RUN ln -s /app /home/rstudio/app

# --- ステージ2: 研究が足すシステムパッケージ（共通ベースか system の上。make lock はここまで）（DOCKER.md 2 節）---
FROM ${RUNTIME_BASE} AS bootstrap
ARG DEBIAN_FRONTEND=noninteractive

# --- 層6: 研究プロジェクトが足すシステムパッケージ（第4〜5層の余白）（DOCKER.md 2 節）---
COPY --chmod=644 docker/project_apt.txt /opt/project_apt.txt
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    packages="$(sed -e 's/#.*//' /opt/project_apt.txt | xargs)" \
    && if [ -n "${packages}" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends ${packages}; \
       fi

# --- ステージ3: 依存（make base はここまでで共通ベースになる。研究では共通ベースに無いものだけが入る）（DOCKER.md 2 節）---
FROM bootstrap AS deps
ARG BASE_IMAGE

# --- 層7: 依存のインストール（DOCKER.md 2 節）---
COPY renv.lock ./
RUN --mount=type=cache,target=/opt/renv/cache \
    R -q -e "source('/opt/p3m_repo.R'); use_p3m(Sys.getenv('P3M_SNAPSHOT')); \
             lock <- renv::lockfile_read('renv.lock'); \
             r_locked <- lock\$R\$Version; \
             r_actual <- paste(R.version\$major, R.version\$minor, sep = '.'); \
             if (!identical(r_locked, r_actual)) \
               stop(sprintf('renv.lock は R %s 用ですが、イメージの R は %s です。BASE_IMAGE を変えたなら make lock で作り直してください。', r_locked, r_actual)); \
             urls <- unlist(lapply(lock\$R\$Repositories, function(r) if (is.list(r)) r\$URL else r)); \
             if (!any(grepl(Sys.getenv('P3M_SNAPSHOT'), urls, fixed = TRUE))) \
               stop(sprintf('renv.lock の取得元（%s）に P3M_SNAPSHOT=%s が含まれません。日付を変えたなら make lock で作り直してください。', paste(urls, collapse = ', '), Sys.getenv('P3M_SNAPSHOT'))); \
             recorded <- lock\$Packages\$renv\$Version; \
             if (is.null(recorded)) \
               stop('renv.lock に renv 自身が載っていません。make lock で作り直してください。'); \
             actual <- as.character(packageVersion('renv')); \
             if (!identical(recorded, actual)) \
               stop(sprintf('renv.lock は renv %s で作られていますが、イメージの renv は %s です。make lock で作り直してください。', recorded, actual)); \
             renv::restore(lockfile = 'renv.lock', library = Sys.getenv('RENV_PATHS_LIBRARY'), prompt = FALSE)" \
    && chown root:root /opt/renv /opt/renv/library \
    && rm -rf /root/.cache/R

# --- ステージ4: 本体（DOCKER.md 2 節）---
FROM deps AS dev
ARG BASE_IMAGE

# --- 層8: RStudio Server の設定（DOCKER.md 2 節）---
COPY --chmod=644 <<'EOF' /etc/rstudio/rstudio-prefs.json
{
  "initial_working_directory": "/app",
  "panes": {
    "quadrants": ["Source", "Console", "TabSet1", "TabSet2"],
    "tabSet1": ["Environment", "History", "Presentation"],
    "tabSet2": ["Files", "Plots", "Help", "Viewer"],
    "hiddenTabSet": ["Connections", "Packages", "Build", "VCS", "Tutorial", "Chat", "Presentations"],
    "console_left_on_top": false,
    "console_right_on_top": true,
    "additional_source_columns": 0,
    "sidebar": [],
    "sidebar_visible": false,
    "sidebar_location": "left"
  },
  "global_theme": "alternate",
  "editor_theme": "Tomorrow Night",
  "font_size_points": 13,
  "help_font_size_points": 12,
  "server_editor_font_enabled": true,
  "server_editor_font": "UDEV Gothic 35",
  "browser_fixed_width_fonts": ["UDEV Gothic 35", "UDEV Gothic 35LG", "Menlo", "Monaco", "Courier New"],
  "highlight_selected_line": true,
  "highlight_selected_word": true,
  "blinking_cursor": false,
  "reduced_motion": true,
  "indent_guides": "gray",
  "rainbow_parentheses": true,
  "highlight_r_function_calls": true,
  "syntax_color_console": true,
  "highlight_console_errors": true,
  "show_margin": true,
  "margin_column": 80,
  "scroll_past_end_of_document": true,
  "console_double_click_select": true,
  "insert_native_pipe_operator": true,
  "strip_trailing_whitespace": true,
  "auto_append_newline": true,
  "save_workspace": "never",
  "load_workspace": false,
  "always_save_history": false
}
EOF

# --- 層9: 研究プロジェクトが足すビルドの手順（第4〜5層の余白）（DOCKER.md 2 節）---
COPY --chmod=644 docker/project_build.sh /opt/project_build.sh
RUN sh -eu /opt/project_build.sh

# --- 層10: ソース投入（DOCKER.md 2 節）---
COPY . .

# --- 層11: ビルド素性の焼き込み（DOCKER.md 2 節）---
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG IMAGE_NAME=unknown
ARG RUNTIME_BASE
ARG RUNTIME_BASE_ID=unknown

RUN BASE_IMAGE_ARG="${BASE_IMAGE}" \
    BUILD_DATE_ARG="${BUILD_DATE}" \
    VCS_REF_ARG="${VCS_REF}" \
    IMAGE_NAME_ARG="${IMAGE_NAME}" \
    RUNTIME_BASE_ARG="${RUNTIME_BASE}" \
    RUNTIME_BASE_ID_ARG="${RUNTIME_BASE_ID}" \
    Rscript --vanilla docker/write_build_info.R \
    && chown root:root /opt/renv/cache

# --- 層12: 読み込み検査（DOCKER.md 2 節）---
USER rstudio
RUN Rscript --vanilla docker/smoke_load.R
USER root
