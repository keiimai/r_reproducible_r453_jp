#!/usr/bin/env Rscript
# --- ビルド素性を /opt/build-info.json に焼き込む（DOCKER.md 2 節）---

# --- x が NULL なら既定値を返す（DOCKER.md 2 節）---
`%||%` <- function(x, default) if (is.null(x)) default else x # nolint: object_name_linter.

# --- 書き出し先（DOCKER.md 2 節）---
OUTPUT_PATH <- "/opt/build-info.json"

# --- 研究プロジェクトが足すビルドの手順（層9 が置く）（DOCKER.md 2 節）---
PROJECT_BUILD_PATH <- "/opt/project_build.sh"

# --- 記録するスレッド数の環境変数（DOCKER.md 2 節）---
THREAD_ENV_VARS <- c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")

# --- 未指定とみなす値（DOCKER.md 2 節）---
ABSENT <- c("", "unknown", "none", "null")

# --- ビルド引数を読む。未指定なら NULL を返す（DOCKER.md 2 節）---
build_arg <- function(name) {
  value <- trimws(Sys.getenv(name, unset = ""))
  if (tolower(value) %in% ABSENT) NULL else value
}

# --- 今の時刻（UTC）（DOCKER.md 2 節）---
now_utc <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# --- ビルドの日時（渡されなければ、下でビルドした時刻を使う）（DOCKER.md 2 節）---
build_date <- build_arg("BUILD_DATE_ARG")

# --- 書き出す中身（DOCKER.md 2 節）---
payload <- list(
  schema_version = 1L,
  image = build_arg("IMAGE_NAME_ARG"),
  base_image = build_arg("BASE_IMAGE_ARG"),
  runtime_base = build_arg("RUNTIME_BASE_ARG"),
  runtime_base_id = build_arg("RUNTIME_BASE_ID_ARG"),
  project_build_sha256 = if (file.exists(PROJECT_BUILD_PATH)) {
    digest::digest(PROJECT_BUILD_PATH, algo = "sha256", file = TRUE)
  },
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  r_version_string = R.version.string,
  renv_version = as.character(utils::packageVersion("renv")),
  p3m_snapshot = Sys.getenv("P3M_SNAPSHOT"),
  build_date = if (is.null(build_date)) now_utc() else build_date,
  build_date_source = if (is.null(build_date)) "build-time clock" else "build-arg",
  vcs_ref = build_arg("VCS_REF_ARG") %||% "unknown",
  platform = R.version$platform,
  library_path = Sys.getenv("RENV_PATHS_LIBRARY"),
  thread_env = as.list(Sys.getenv(THREAD_ENV_VARS)),
  locale = list(LANG = Sys.getenv("LANG"), LC_ALL = Sys.getenv("LC_ALL")),
  timezone = Sys.getenv("TZ")
)

# --- JSON にして書き出す（DOCKER.md 2 節）---
json <- jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, null = "null")
writeLines(json, OUTPUT_PATH, useBytes = TRUE)

# --- 主な値をビルドのログに出す（DOCKER.md 2 節）---
cat(sprintf("[build-info] %s を書き出しました\n", OUTPUT_PATH))
for (key in c("image", "base_image", "r_version", "renv_version", "p3m_snapshot", "build_date",
              "vcs_ref", "runtime_base")) {
  cat(sprintf("  %-14s: %s\n", key, payload[[key]] %||% "(未指定)"))
}
# --- コミットが分からないときは注意を出す（DOCKER.md 2 節）---
if (identical(payload$vcs_ref, "unknown")) {
  cat(
    "  [注意] vcs_ref が unknown です。このイメージがどのコミットから作られたかを\n",
    "         後から辿れません。git 化を飛ばしたか、make build を使わずに\n",
    "         ビルドした可能性があります。\n",
    sep = ""
  )
}
