#!/usr/bin/env Rscript
# --- renv.lock を DESCRIPTION から作り直す（make lock）。--check は確かめるだけ（make lock-check）（DOCKER.md 2 節）---

# --- リポジトリの根で走らせる（DESCRIPTION を読む）（WORKSPACE.md 2 節）---
stopifnot(file.exists("DESCRIPTION"))

# --- DESCRIPTION の欄から、パッケージ名と版の指定（例: >= 2.3）を取り出す（WORKSPACE.md 2 節）---
parse_requirements <- function(fields) {
  raw <- read.dcf("DESCRIPTION", fields = fields)[1, ]
  entries <- trimws(unlist(strsplit(raw[!is.na(raw)], ",")))
  entries <- entries[nzchar(entries)]
  data.frame(
    name = sub("[[:space:]]*\\(.*\\)$", "", entries),
    spec = ifelse(grepl("(", entries, fixed = TRUE),
                  sub("^[^(]*\\(([^)]*)\\).*$", "\\1", entries), ""),
    stringsAsFactors = FALSE
  )
}

# --- DESCRIPTION の欄からパッケージ名だけを取り出す（WORKSPACE.md 2 節）---
parse_dependencies <- function(field) {
  names <- parse_requirements(field)$name
  sort(unique(names[names != "R"]))
}

# --- 版が指定（>=・>・==・<=・<）を満たすか（WORKSPACE.md 2 節）---
satisfies <- function(version, spec) {
  if (!nzchar(spec)) return(TRUE)
  operator <- sub("^[[:space:]]*([<>=]+).*$", "\\1", spec)
  wanted <- package_version(trimws(sub("^[[:space:]]*[<>=]+", "", spec)))
  found <- package_version(version)
  switch(operator,
         ">=" = found >= wanted, ">" = found > wanted, "==" = found == wanted,
         "<=" = found <= wanted, "<" = found < wanted, FALSE)
}

# --- renv.lock の 1 件が依存するパッケージの名前（renv 1.0 は Requirements に書く）（WORKSPACE.md 2 節）---
lock_dependencies <- function(record) {
  raw <- unlist(record[c("Depends", "Imports", "LinkingTo", "Requirements")], use.names = FALSE)
  sub("[[:space:]]*\\(.*\\)$", "", trimws(as.character(raw)))
}

# --- make lock-check: renv.lock を書き換えずに、DESCRIPTION と食い違っていないかだけを確かめる（WORKSPACE.md 2 節）---
if ("--check" %in% commandArgs(trailingOnly = TRUE)) {
  if (!file.exists("renv.lock")) {
    cat("[lock-check] renv.lock がありません。make lock で作ってください。\n", file = stderr())
    quit(status = 1L)
  }
  base_packages <- rownames(utils::installed.packages(priority = "base"))
  lock <- jsonlite::read_json("renv.lock")$Packages
  declared <- parse_requirements(c("Imports", "Suggests", "Config/Needs/project"))
  declared <- declared[!declared$name %in% c("R", base_packages), , drop = FALSE]
  problems <- character(0)

  # --- 宣言したものが載っていて、版の指定を満たすか（WORKSPACE.md 2 節）---
  for (i in seq_len(nrow(declared))) {
    record <- lock[[declared$name[i]]]
    if (is.null(record)) {
      problems <- c(problems, sprintf("%s: DESCRIPTION にあるのに、renv.lock に無い", declared$name[i]))
    } else if (!satisfies(record$Version, declared$spec[i])) {
      problems <- c(problems, sprintf("%s: DESCRIPTION は %s、renv.lock は %s",
                                      declared$name[i], declared$spec[i], record$Version))
    }
  }
  if (is.null(lock[["renv"]])) problems <- c(problems, "renv: renv.lock に renv 自身が無い")

  # --- 宣言したものと renv から依存をたどり、足りないものと、たどれない残りものを探す（WORKSPACE.md 2 節）---
  reachable <- character(0)
  queue <- intersect(c(declared$name, "renv"), names(lock))
  while (length(queue) > 0L) {
    reachable <- union(reachable, queue)
    needed <- setdiff(unlist(lapply(lock[queue], lock_dependencies)), c("R", base_packages))
    absent <- setdiff(needed, names(lock))
    if (length(absent) > 0L) {
      problems <- c(problems, sprintf("%s: renv.lock のパッケージが依存するのに、renv.lock に無い", absent))
    }
    queue <- setdiff(intersect(needed, names(lock)), reachable)
  }
  stale <- setdiff(names(lock), reachable)
  if (length(stale) > 0L) {
    problems <- c(problems, sprintf("%s: renv.lock にあるのに、DESCRIPTION からたどれない", stale))
  }

  # --- 食い違いがあれば並べて止める（WORKSPACE.md 2 節）---
  if (length(problems) > 0L) {
    cat("[lock-check] renv.lock が DESCRIPTION と食い違っています。make lock で作り直してください:\n",
        paste0("  - ", unique(problems), collapse = "\n"), "\n", sep = "", file = stderr())
    quit(status = 1L)
  }
  cat(sprintf("[lock-check] renv.lock は DESCRIPTION と合っています（宣言 %d・renv.lock %d パッケージ）\n",
              nrow(declared), length(lock)))
  quit(status = 0L)
}

# --- 取得元を P3M の日付に向ける（DOCKER.md 2 節）---
snapshot_date <- Sys.getenv("P3M_SNAPSHOT", unset = "")
source("/opt/p3m_repo.R")
repo <- use_p3m(snapshot_date)
cat(sprintf("[lock] 取得元: %s\n", repo))

# --- 入れる先はプロジェクトライブラリ（WORKSPACE.md 2 節）---
library_path <- Sys.getenv("RENV_PATHS_LIBRARY", unset = "/opt/renv/library")
.libPaths(c(library_path, .libPaths()))
cat(sprintf("[lock] ライブラリ: %s\n", library_path))

# --- 依存の Suggests まではたどらない（WORKSPACE.md 2 節）---
renv::settings$package.dependency.fields(c("Imports", "Depends", "LinkingTo"), persist = FALSE)

# --- 入れるもの: DESCRIPTION が宣言したものと renv（WORKSPACE.md 2 節）---
declared <- unique(c(
  parse_dependencies("Imports"),
  parse_dependencies("Suggests"),
  parse_dependencies("Config/Needs/project")
))
base_packages <- rownames(utils::installed.packages(priority = "base"))
required <- setdiff(union(declared, "renv"), base_packages)

# --- プロジェクトライブラリに入っているもの（WORKSPACE.md 2 節）---
in_project_library <- function() {
  rownames(utils::installed.packages(lib.loc = library_path))
}

# --- 宣言したものが取得元にあるか（WORKSPACE.md 2 節）---
available <- utils::available.packages()
unknown <- setdiff(required, rownames(available))
if (length(unknown) > 0L) {
  stop(sprintf(
    "取得元（%s）に無いパッケージがあります: %s\n名前の綴りと、その日付の CRAN にあるかを確かめてください。",
    repo, paste(unknown, collapse = ", ")
  ))
}

# --- 宣言したものを入れる（WORKSPACE.md 2 節）---
cat("[lock] DESCRIPTION の宣言を導入します\n")
tryCatch(
  renv::install(required),
  error = function(e) {
    cat("[lock] renv::install() が一部失敗しました: ", conditionMessage(e), "\n", sep = "")
  }
)

# --- 依存をたどったものも、プロジェクトライブラリに入れる（WORKSPACE.md 2 節）---
closure <- unique(c(required, unlist(tools::package_dependencies(
  required, db = available, which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE
))))
closure <- setdiff(closure, c(base_packages, "R"))
missing <- setdiff(closure, in_project_library())
if (length(missing) > 0L) {
  cat(sprintf(
    "[lock] プロジェクトライブラリに無いものを明示的に入れます: %s\n",
    paste(missing, collapse = ", ")
  ))
  utils::install.packages(missing, lib = library_path)
}

# --- 宣言したものがすべて入ったか（WORKSPACE.md 2 節）---
still_missing <- setdiff(required, in_project_library())
if (length(still_missing) > 0L) {
  stop(sprintf(
    "DESCRIPTION が宣言したパッケージが %s に入りませんでした: %s\n上のログのビルドエラーを確認してください。",
    library_path, paste(still_missing, collapse = ", ")
  ))
}

# --- 入っただけでは足りない。依存をたどったものまで、読み込めるかを確かめる（WORKSPACE.md 2 節）---
unloadable <- character(0)
for (package in closure) {
  reason <- tryCatch(
    {
      suppressWarnings(loadNamespace(package))
      NULL
    },
    error = function(e) gsub("\n", "\n      ", trimws(conditionMessage(e)), fixed = TRUE)
  )
  if (!is.null(reason)) {
    unloadable <- c(unloadable, sprintf("  - %s: %s", package, reason))
  }
}
if (length(unloadable) > 0L) {
  hint <- if (any(grepl("cannot open shared object file", unloadable, fixed = TRUE))) {
    paste0(
      "システムの共有ライブラリ（上の *.so.N）が足りません。その .so を含む apt パッケージ\n",
      "（-dev の側）を docker/project_apt.txt に足してから、make lock をやり直してください。"
    )
  } else {
    "上のエラーを確認してください。"
  }
  stop(sprintf(
    "入りましたが読み込めないパッケージがあります（renv.lock は書き換えていません）:\n%s\n\n%s",
    paste(unloadable, collapse = "\n"), hint
  ))
}

# --- プロジェクトライブラリだけを記録する（WORKSPACE.md 2 節）---
snapshot_ok <- tryCatch(
  {
    renv::snapshot(library = library_path, packages = required, prompt = FALSE)
    TRUE
  },
  error = function(e) {
    cat("[lock] renv の事前検査で止まりました: ", conditionMessage(e), "\n", sep = "")
    FALSE
  }
)
if (!snapshot_ok) {
  cat("[lock] 事前検査を飛ばして書き出します（宣言の充足はこのスクリプトが検査する）\n")
  renv::snapshot(library = library_path, packages = required, prompt = FALSE, force = TRUE)
}

# --- 書いた renv.lock を読み直して確かめる（WORKSPACE.md 2 節）---
lock <- renv::lockfile_read("renv.lock")
urls <- as.character(unlist(lock$R$Repositories, use.names = FALSE))
if (!any(grepl(snapshot_date, urls, fixed = TRUE))) {
  stop(sprintf(
    "renv.lock の Repositories に %s が入っていません: %s",
    snapshot_date, paste(urls, collapse = ", ")
  ))
}
if (is.null(lock$Packages[["renv"]])) {
  stop("renv.lock に renv 自身が入っていません（restore が自分を復元できません）。")
}
recorded <- names(lock$Packages)
outside <- setdiff(recorded, in_project_library())
if (length(outside) > 0L) {
  stop(sprintf(
    "renv.lock にプロジェクトライブラリに無いパッケージが載っています: %s",
    paste(outside, collapse = ", ")
  ))
}
absent <- setdiff(required, recorded)
if (length(absent) > 0L) {
  stop(sprintf(
    "DESCRIPTION が宣言したのに renv.lock に載らなかったものがあります: %s",
    paste(absent, collapse = ", ")
  ))
}

# --- 読み込みを確かめた数と renv.lock の中身、次の手順を出す（WORKSPACE.md 2 節）---
cat(sprintf(
  "\n[lock] 依存をたどった %d パッケージの読み込みを確かめた。renv.lock は %d パッケージ / R %s / %s\n",
  length(closure), length(lock$Packages), lock$R$Version, snapshot_date
))
cat("[lock] renv.lock が変わったか、docker/project_apt.txt を変えたなら、次に make build\n")
