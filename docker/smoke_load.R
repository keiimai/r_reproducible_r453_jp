#!/usr/bin/env Rscript
# --- 出荷前の読み込み検査（DOCKER.md 2 節）---
# --- DESCRIPTION の欄からパッケージ名だけを取り出す（DOCKER.md 2 節）---
parse_dependencies <- function(field) {
  raw <- read.dcf("DESCRIPTION", fields = field)[1, 1]
  if (is.na(raw)) return(character(0))
  names <- trimws(strsplit(raw, ",")[[1]])
  names <- sub("[[:space:]]*\\(.*\\)$", "", names)
  names <- names[nzchar(names) & names != "R"]
  sort(unique(names))
}

# --- CMD が使う実行ファイル（起動はさせない）（DOCKER.md 2 節）---
REQUIRED_EXECUTABLES <- list(
  list("/init", "rocker/rstudio の起動処理（イメージの CMD そのもの）"),
  list("rserver", "RStudio Server の本体（/init が起動する）")
)

# --- 失敗を記録する入れ物（DOCKER.md 2 節）---
failures <- character(0)
unloadable <- character(0)

# --- 読み込みを試し、失敗したらその理由を返す（NULL なら成功）（DOCKER.md 2 節）---
load_error <- function(package) {
  tryCatch(
    {
      suppressWarnings(loadNamespace(package))
      NULL
    },
    error = function(e) gsub("\n", "\n      ", trimws(conditionMessage(e)), fixed = TRUE)
  )
}

# --- 版を 1 行ずつ出すもの（renv と DESCRIPTION の依存すべて）（DOCKER.md 2 節）---
declared <- unique(c(
  "renv",
  parse_dependencies("Imports"),
  parse_dependencies("Suggests"),
  parse_dependencies("Config/Needs/project")
))

# --- 読めなければ止めるもの（上と、renv.lock のすべてのパッケージ）（DOCKER.md 2 節）---
required <- union(declared, names(jsonlite::read_json("renv.lock")$Packages))
for (package in required) {
  reason <- load_error(package)
  if (!is.null(reason)) {
    failures <- c(failures, sprintf("%s: 読み込めません\n      %s", package, reason))
    unloadable <- c(unloadable, reason)
  } else if (package %in% declared) {
    cat(sprintf("[smoke] %-14s %s\n", package, as.character(utils::packageVersion(package))))
  }
}

# --- quarto が在り、R エンジンが動くか（DOCKER.md 2 節）---
quarto <- Sys.which("quarto")
if (!nzchar(quarto)) {
  failures <- c(failures, "quarto: 見つかりません（notebooks/*.qmd をレンダリングできません）")
} else {
  cat(sprintf("[smoke] %-14s %s\n", "quarto", quarto))
  engine <- c("knitr", "rmarkdown")
  absent <- engine[!vapply(engine, function(p) {
    suppressWarnings(requireNamespace(p, quietly = TRUE))
  }, logical(1))]
  if (length(absent) > 0L) {
    failures <- c(failures, sprintf(
      "quarto: knitr エンジンに要る %s が読み込めません（notebooks/*.qmd をレンダリングできません）",
      paste(absent, collapse = " / ")
    ))
  } else {
    report <- suppressWarnings(
      system2(quarto, c("check", "knitr"), stdout = TRUE, stderr = TRUE)
    )
    code <- attr(report, "status")
    if ((!is.null(code) && !identical(as.integer(code), 0L)) ||
          any(grepl("not available|ERROR", report))) {
      failures <- c(failures, paste0(
        "quarto: knitr エンジンが動きません（notebooks/*.qmd をレンダリングできません）\n",
        paste0("      ", trimws(utils::tail(report, 3)), collapse = "\n")
      ))
    } else {
      cat(sprintf("[smoke] %-14s R チャンクを処理できる\n", "quarto engine"))
    }
  }
}

# --- CMD が使う実行ファイルが在り、rstudio が実行できるか（DOCKER.md 2 節）---
for (probe in REQUIRED_EXECUTABLES) {
  name <- probe[[1]]
  path <- if (startsWith(name, "/")) name else Sys.which(name)
  if (!nzchar(path) || !file.exists(path)) {
    failures <- c(failures, sprintf("%s: 見つかりません（%s）", name, probe[[2]]))
    next
  }
  if (file.access(path, 1L) != 0L) {
    failures <- c(failures, sprintf("%s: 実行権がありません: %s", name, path))
    next
  }
  cat(sprintf("[smoke] %-14s %s\n", basename(name), path))
}

# --- 日本語フォントが入っているか（DOCKER.md 2 節）---
families <- tryCatch(
  system2("fc-list", c(":lang=ja", "family"), stdout = TRUE, stderr = FALSE),
  error = function(e) character(0)
)
if (length(families) == 0L) {
  failures <- c(failures, "日本語フォントがイメージに入っていません")
} else {
  cat(sprintf("[smoke] %-14s %d 件\n", "日本語フォント", length(families)))
}

# --- R/ の構文（DOCKER.md 2 節）---
sources <- list.files("R", pattern = "[.][Rr]$", full.names = TRUE)
for (file in sources) {
  parsed <- tryCatch(parse(file), error = function(e) e)
  if (inherits(parsed, "error")) {
    failures <- c(failures, sprintf("%s: 構文エラー: %s", file, conditionMessage(parsed)))
  }
}

# --- 問題があれば並べて直し方を案内し、ビルドを止める（DOCKER.md 4 節）---
if (length(failures) > 0L) {
  cat("\nビルド検査に失敗しました:\n", file = stderr())
  for (failure in failures) cat("  - ", failure, "\n", sep = "", file = stderr())
  missing_library <- grepl("cannot open shared object file", unloadable, fixed = TRUE)
  if (any(missing_library)) {
    cat(
      "\nシステムの共有ライブラリ（上の *.so.N）が足りません。P3M のバイナリは R のパッケージだけを\n",
      "持ってきて、それが実行時に使う共有ライブラリは持ってこないためです。\n",
      "その .so を含む apt パッケージ（-dev の側。docs/DOCKER.md 4 節）を docker/project_apt.txt に足して、次を実行してください:\n",
      "  make lock\n",
      "  make build\n",
      sep = "", file = stderr()
    )
  }
  if (!all(missing_library)) {
    cat(
      "\nrenv.lock と DESCRIPTION の整合性を確認してください:\n",
      "  make lock\n",
      "  make build\n",
      sep = "", file = stderr()
    )
  }
  quit(status = 1L)
}

# --- 通ったことを 1 行で出す（DOCKER.md 2 節）---
cat(sprintf(
  "[smoke] %d パッケージの読み込みに成功（R/ %d ファイルの構文も検査）\n",
  length(required), length(sources)
))
