@~/.codex/AGENTS.md

# Claude Code

共通の指示は上の `~/.codex/AGENTS.md`（このリポジトリの codex/AGENTS.md）にある。ここには Claude Code だけのことを書く。

## ユーザーの判断を求める場合はAskUserQuestionを利用

ユーザーに選択、判断を求める場合はAskUserQuestionツールを使うこと。
自由入力（Other）で質問や確認が返ってきたら、次のターンではAskUserQuestionを使わず、普通の文章で答える。まだ選んでもらうことが残っていれば、その次のターンで改めて使う。
