# config-files

macOSの開発環境のdotfiles・設定ファイルを一元管理するリポジトリ。

## 重要: ファイル編集のルール

設定ファイルを変更する際は、`~/` 以下のファイルを直接編集してはいけない。必ずこのリポジトリ内のファイルを編集すること。

`mise bootstrap`（`mise/config.toml` の `[dotfiles]` など）によって、このリポジトリ内のファイルから `~/` 以下へシンボリックリンクが貼られている。そのため、このリポジトリ内のファイルを編集すれば `~/` 側にも自動的に反映される。

ただし `~/.claude/settings.json` と `~/.codex/config.toml` はアプリが自分でも書き換えるので、リンクではなく、`mise bootstrap` が `claude/settings.json` と `codex/config.toml` に書いたキーだけをマージしている。共通の設定はリポジトリ側を編集し、`mise bootstrap` で反映する。`~/` 側にだけあるキー（その場で許可した権限、Orcaのhooks、Codexが書くパスなど）はそのMacのもので、リポジトリには入れない。

## スクリプトの配置

`bin/` は他のリポジトリでも使う汎用コマンド用。このリポジトリ専用のスクリプトは `bin/` に置かず、`scripts/` に配置する。

## タスク

このリポジトリのタスクは `Makefile` に書く。新しいMacで最初から使えるのはmakeだけなので、グローバルの指示（タスクはjustfile）の例外にしている。justfileは作らない。

## git

commitとpushは、ユーザーに指示されたときだけ行う。変更を終えたら、commitせずに報告して指示を待つ。commitを指示されても、pushは指示されるまで行わない。
