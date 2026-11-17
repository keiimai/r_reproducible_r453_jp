# --- P3M（CRAN スナップショット）の取得元 URL（DOCKER.md 2 節）---
P3M_BASE <- "https://packagemanager.posit.co/cran"

# --- URL に入れる OS の版の名前を /etc/os-release から読む（DOCKER.md 1 節）---
os_release_field <- function(key) {
  if (!file.exists("/etc/os-release")) return("")
  lines <- readLines("/etc/os-release", warn = FALSE)
  hit <- grep(paste0("^", key, "="), lines, value = TRUE)
  if (length(hit) == 0L) return("")
  gsub('"', "", sub(paste0("^", key, "="), "", hit[1]))
}

# --- 日付から取得元 URL を作る（DOCKER.md 2 節）---
p3m_repo <- function(snapshot) {
  if (!nzchar(snapshot)) {
    stop("P3M_SNAPSHOT が未設定です。Dockerfile の ARG P3M_SNAPSHOT（CI では ci.yml の env）で決めます。")
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", snapshot)) {
    stop("P3M_SNAPSHOT は YYYY-MM-DD の日付である必要があります: ", snapshot)
  }
  source_url <- paste(P3M_BASE, snapshot, sep = "/")
  codename <- os_release_field("VERSION_CODENAME")
  if (!nzchar(codename)) return(source_url)
  paste(P3M_BASE, "__linux__", codename, snapshot, sep = "/")
}

# --- 取得元を設定して URL を返す（HTTPUserAgent も要る）（DOCKER.md 1 節）---
use_p3m <- function(snapshot = Sys.getenv("P3M_SNAPSHOT")) {
  url <- p3m_repo(snapshot)
  options(
    repos = c(P3M = url),
    HTTPUserAgent = sprintf(
      "R/%s R (%s)", getRversion(),
      paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
    )
  )
  url
}
