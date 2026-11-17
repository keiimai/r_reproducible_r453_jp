# 環境構築の手順

このテンプレートから研究プロジェクトを起こし、最初の検査が通るまでの手順である。

---

## 0. 前提条件

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [git](https://git-scm.com/docs/git) 2.54 以降（マージのコミットの検査に使う）
- Dev Container を使うなら [VS Code](https://code.visualstudio.com/) と拡張機能 [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

R・renv・RStudio はホストに入れない（イメージの中にある）。

---

## 1. 新しいプロジェクトを起こす

### 手順 1 — フォルダを用意する

```bash
mkdir -p ~/path/to/myproject
git -C r_453_jp archive HEAD | tar -x -C ~/path/to/myproject
cd ~/path/to/myproject
```

[`git archive`](https://git-scm.com/docs/git-archive) で取り出すのは push 済みのコミットにし、そのコミット（`git -C r_453_jp rev-parse HEAD`）を `CHANGELOG.md` の冒頭の欄に書く。

### 手順 2 — git 化して、初回コミットする

```bash
git init -b main
git config user.name "<名前>" && git config user.email "<メール>"
git add -A
git commit -m "chore: テンプレート r_453_jp の状態を記録"
```

### 手順 3 — 名前を変える

```bash
make rename NAME=myproject
git add -A && git commit -m "chore: 名前を myproject にする"
```

Docker の名前（compose のプロジェクト名・イメージ・コンテナ）の頭に、プロジェクトの名前を付ける。

### 手順 4 — イメージを作る

x64 の PC では、先に `.env` に `PLATFORM=linux/amd64` と書く（→ [`DOCKER.md`](DOCKER.md) 1 節）。

```bash
make build
```

初回は数分かかる。通ると、ログの終わり近くに `[smoke] <数> パッケージの読み込みに成功` の行が出る（最後の検査 → [`DOCKER.md`](DOCKER.md) 2 節の層 12）。この時点で「注意: コミット前のフックが有効になっていません」と出るのは正常である（手順 6 で有効にする）。

### 手順 5 — 初回の動作確認

```bash
make verify
make runs
```

`make runs` で、疎通（`make smoke`）の実行が台帳に載ったことを確かめる（→ [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 2・3 節）。

### 手順 6 — フックを有効にする

```bash
make hooks
make hooks-all
```

2 つの命令がすることと検査の中身 → [`WORKSPACE.md`](WORKSPACE.md) 3 節。

---

## 2. 起動の 2 経路

2 つの経路は同じイメージと同じコンテナ（`<名前>_dev`）を使うので、同時には使わない（切り替えるときは、片方を閉じてから開く）。

### 2-A. RStudio Server

```bash
make up
```

ポートと認証 → [`DOCKER.md`](DOCKER.md) 3 節。

### 2-B. VS Code の Dev Container

[`Dev Containers: Reopen in Container`](https://code.visualstudio.com/docs/devcontainers/containers) で開く。テンプレートの取り込みで `devcontainer.json` が変わったときと `make build` のあとは、[`Dev Containers: Rebuild Container`](https://code.visualstudio.com/docs/devcontainers/create-dev-container) で開き直す（→ [`DOCKER.md`](DOCKER.md) 3 節）。

---

## 3. 落とし穴

イメージのビルドと実行に関わるものは [`DOCKER.md`](DOCKER.md) 4 節にある。

| 表示 | 原因 | 対処 |
|---|---|---|
| `fatal: not a git repository` | 手順 2 を飛ばした | 手順 2 から |
