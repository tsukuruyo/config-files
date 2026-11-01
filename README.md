# config-files

Macのdotfiles・パッケージ・設定を、[mise bootstrap](https://mise.jdx.dev/bootstrap.html)で管理する。

## 新しいMac

- Xcode Command Line Toolsを入れる（`xcode-select --install`）。初期状態のmacOSにはgitの実体がないため
- ~/development/config-filesにHTTPSでcloneする（`git clone https://github.com/tsukuruyo/config-files.git ~/development/config-files`）。SSH鍵はBitwardenで管理しており、この時点ではBitwardenが無いためSSHではcloneできない
- `make bootstrap PROFILE=personal` か `make bootstrap PROFILE=work` を実行する。最後に表示されるコマンドを実行して、今のシェルにbrewのPATHを通す
- App StoreにApple Accountでサインインしておく。`mas:` の項目（Xcodeなど）は `mas` で入れるため、サインインが必要
- `~/.local/bin/mise bootstrap` を実行する。`brew:mas` が入ると同じ実行の中で `mas:` の項目も入る。最後のfollow-upに `mas: ... skipped (mas not found)` と出るのは実行前の予定がそのまま表示されたもので、途中に `mise mas:` の行が出ていれば問題ない
- BitwardenにログインしてSSH agentを有効化し、~/.ssh/configの先頭に `Include ~/development/config-files/ssh/config` を書く
- originをSSHに切り替える（`git remote set-url origin git@github.com:tsukuruyo/config-files.git`）

## 日々の同期

- `git pull` してから `mise bootstrap` を実行する。宣言との差分だけが適用される

## 構成

| ファイル | 役割 |
| --- | --- |
| `Makefile` | `make bootstrap` だけを持つ。新しいMacで最初から使えるタスクランナーはmakeだけのため |
| `scripts/bootstrap.sh` | Homebrewとmiseを入れ、`mise/` を `~/.config/mise` にリンクする |
| `mise/config.toml` | すべてのMacで共通の設定 |
| `mise/config.personal.toml` | 私物Macだけの設定 |
| `mise/config.work.toml` | 仕事Macだけの設定。公開リポジトリなので社内ツールの名前などは書かない |
| `~/.config/mise/miserc.local.toml` | Macごとにenvを選ぶ。`scripts/bootstrap.sh` が最初に1回だけ書き、Git管理しない |
| `ssh/config` | SSHのホスト設定。`~/.ssh/config` からIncludeする |

## パッケージ

- `scripts/bootstrap.sh` が入れるのはHomebrewとmiseだけ。アプリやツールはすべて `[bootstrap.packages]` に書き、`mise bootstrap` で入れる
- 新しいMacでも必ず入れたいものだけを書く。アドホックに `brew install` したものは書かなくてよい
- 片方のMacでしか使わないものは、`mise/config.toml` ではなく `mise/config.personal.toml` か `mise/config.work.toml` に書く
- `mise bootstrap packages status --missing` で、宣言した項目が揃っているか確認できる
- `mise bootstrap packages prune --dry-run` で、宣言にないformulaを一覧できる。`--dry-run` を外すと実際に削除される
- 宣言にないcaskとApp Storeのアプリはpruneでは検出できない。`brew list --cask` と `mas list` を目で見る
- 手動でインストール済みのcaskは、`[bootstrap.brew] adopt = true` によりbrew管理下に取り込まれる

## 参考

- [mise bootstrapで私物Macと仕事Macの設定を管理する](https://blog.shibayu36.org/entry/2026/10/13/173000)（blog.shibayu36.org）
