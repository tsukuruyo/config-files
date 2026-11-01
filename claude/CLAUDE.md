@~/.codex/AGENTS.md

<!-- 共通の指示は、上で読み込む ~/.codex/AGENTS.md（このリポジトリの codex/AGENTS.md）に書く。ここには Claude Code だけのことを書く。このコメントは Claude Code に読み込まれない -->

# Claude Code

## ユーザーの判断を求めるとき

- 選択肢を示すときは AskUserQuestion ツールを使う
- 自由入力（Other）で質問や確認が返ってきたら、次のターンでは AskUserQuestion を使わずに文章で答える。まだ選んでもらうことが残っていれば、その次のターンで改めて使う
