@~/.codex/AGENTS.md

## サンドボックスの外で動かすコマンド

gh、unity、docker build / compose / ps / logs / images、dotnet format、
git の clone / fetch / pull / push / merge / switch / ls-remote / submodule update は、
サンドボックスの外で動かす設定になっている。

- 1回の Bash 呼び出しには、そのコマンド1つだけを書く
- `|`、`&&`、`;`、ファイルへのリダイレクト、`cd`、`$(...)`、`git -C` と組み合わせない
  （組み合わせるとサンドボックスの中で実行され、認証やネットワークのエラーで失敗する）
- 絞り込みはパイプではなくコマンド自身のオプションで行う
  （例：`gh pr list --json number,title --jq '.[].title'`）
- ブランチの作成と切り替えには `git checkout` ではなく `git switch` を使う
- コンテナの操作は `docker compose` のサブコマンドで行う（`docker run` と `docker exec` は使えない）
- 失敗しても、サンドボックスの外でのやり直しはできない。原因と、実行してほしいコマンドを伝える

