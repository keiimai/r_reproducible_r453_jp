# --- ディレクトリの構成を作る（無いものだけ作り、あるものは飛ばす）（WORKSPACE.md 1 節）---

# --- このファイルのあるフォルダ（リポジトリの根）で動く（WORKSPACE.md 1 節）---
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(script) == 1L) setwd(dirname(normalizePath(script)))

# --- 作るディレクトリ（テンプレートと同じ構成）（WORKSPACE.md 1 節）---
DIRS <- c(
  ".devcontainer", ".githooks", ".github/workflows", ".vscode", "R", "configs",
  "data", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docker", "docs", "docs/definition", "models", "notebooks",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables",
  "tests/testthat", "tools"
)

# --- 新しく作ったときに .gitkeep を置くディレクトリ（中身を Git で追跡しない骨格）（WORKSPACE.md 1 節）---
KEEP <- c(
  "configs", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docs/definition", "models",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables"
)

# --- 無いディレクトリだけを作り、作ったもの・飛ばしたものを出す（WORKSPACE.md 1 節）---
created <- 0L
for (dir in DIRS) {
  if (dir.exists(dir)) {
    cat(sprintf("[setup] 既にあるので飛ばす: %s\n", dir))
    next
  }
  if (file.exists(dir)) stop(sprintf("%s はディレクトリではないファイルです。名前を変えてから、やり直してください。", dir))
  dir.create(dir, recursive = TRUE)
  if (dir %in% KEEP) file.create(file.path(dir, ".gitkeep"))
  cat(sprintf("[setup] 作った: %s\n", dir))
  created <- created + 1L
}
cat(sprintf("[setup] 作った %d 個・飛ばした %d 個\n", created, length(DIRS) - created))
