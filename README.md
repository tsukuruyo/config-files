# config-files

Macのdotfiles・パッケージ・設定を、[mise bootstrap](https://mise.jdx.dev/bootstrap.html)で管理する。

## 新しいMac

- Xcode Command Line Toolsを入れる（`xcode-select --install`）。初期状態のmacOSにはgitの実体がないため
- `~/development/config-files`にHTTPSでcloneする（`git clone https://github.com/tsukuruyo/config-files.git ~/development/config-files`）。SSH鍵はBitwardenで管理しており、この時点ではBitwardenが無いためSSHではcloneできない
- `make bootstrap PROFILE=personal` か `make bootstrap PROFILE=work` を実行する。HomebrewとmiseとOrcaが入る。最後に表示されるコマンドを実行して、今のシェルにbrewのPATHを通す
- App StoreにApple Accountでサインインしておく。`mas:` の項目（Xcodeなど）は `mas` で入れるため、サインインが必要
- `~/.local/bin/mise bootstrap` を実行する。`brew:mas` が入ると同じ実行の中で `mas:` の項目も入る。最後のfollow-upに `mas: ... skipped (mas not found)` と出るのは実行前の予定がそのまま表示されたもので、途中に `mise mas:` の行が出ていれば問題ない
- caskもApp Storeもないアプリを手で入れる
  - DaVinci Resolve: Blackmagic Designのサイト（https://www.blackmagicdesign.com/products/davinciresolve ）から。Blackmagic Proxy Generatorも一緒に入る
  - Blackmagic RAW: Blackmagic Designのサポートページから
  - Synergy: Symlessのサイト（https://symless.com/synergy ）から
  - Reality Converter: Apple Developer（https://developer.apple.com/augmented-reality/tools/ ）から
  - Canon IJ Scan Utility: Canonのサポートページで、プリンターの機種のドライバーと一緒に
- 私物Macでは、Adobe Creative Cloud（`brew-cask:adobe-creative-cloud` で入る）にサインインし、そこからAdobeのアプリを入れる
  - Photoshop・Premiere Pro・Illustrator・After Effects・Audition・Lightroom・Media Encoder・Acrobat
- sudoをTouch IDで通すため、`/etc/pam.d/sudo_local` を次の2行で作る（`sudo vi /etc/pam.d/sudo_local`）。macOSのアップデートでも消えない。1行目の `pam_reattach.so` は `brew:pam-reattach` で入り、Orcaなどの中のターミナルでもTouch IDを使えるようにする
  ```
  auth       optional       /opt/homebrew/lib/pam/pam_reattach.so ignore_ssh
  auth       sufficient     pam_tid.so
  ```
- 新しいターミナルを開く。`~/.zshrc`がこのリポジトリの.zshrcになり、初回はsheldonがGitHubからプラグインを取ってくるので少し時間がかかる（ネットワークが必要）
- Ghosttyを起動し、システム設定 → プライバシーとセキュリティ → アクセシビリティでGhosttyを許可する。quick terminalのグローバルなショートカット（Ctrl+`）に必要なため
- システム設定 → アクセシビリティ → ディスプレイで「ポインタのサイズ」を大きくする（`mouseDriverCursorSize` が3くらい）。defaultsで書くにはフルディスクアクセスが要るので、mise bootstrapでは設定しない
- `make skills` を実行して、Claude CodeとCodexのskillsを入れる
- Orcaを起動し、ホームディレクトリへのアクセスを許可する。初回は`~/.claude`・`~/.codex`・Ghosttyの設定を取り込むかを聞かれる。Orcaは自分でClaude Codeのhooksを`~/.claude/settings.json`に書き足し、以降は自動で更新する
- `~/.gitconfig.local`に `[user]` の `name` と `email` を書く。公開リポジトリなので.gitconfigには書かず、.gitconfigの最後でincludeする。仕事用Macだけの設定は`~/.gitconfig.work`に書く
- BitwardenにログインしてSSH agentを有効化し、`~/.ssh/config`の先頭に `Include ~/development/config-files/ssh/config` を書く
  - Bitwardenの設定の「SSHエージェントを使用する際に認証を要求する」を「Remember until vault is locked」にする。既定の「Always」は鍵を使うたびに承認の画面を出す。こちらは、同じ鍵と接続先なら、保管庫がロックされるまで1回の承認で済む
- originをSSHに切り替える（`git remote set-url origin git@github.com:tsukuruyo/config-files.git`）

## 日々の同期

- `make sync` を実行する。`git pull` してから `mise bootstrap` を実行し、宣言との差分だけが適用される
- `make plan` で、`mise bootstrap` が何を変えるかを実行前に確かめられる。`make status` で、それぞれの部分の状態を見られる
- コミットする前に `make lint` を実行する。shellcheckでシェルスクリプトを検査し、gitleaksで作業ツリーに秘密がないかを探す

## 構成

| ファイル | 役割 |
| --- | --- |
| `Makefile` | このリポジトリのタスク（`bootstrap`・`plan`・`status`・`sync`・`lint`・`skills`）。新しいMacで最初から使えるタスクランナーはmakeだけなので、justfileではなくmakeにする。`brew:just` は、ほかのリポジトリで使うために入れている |
| `scripts/bootstrap.sh` | Homebrew・mise・Orcaを入れ、`mise/` を `~/.config/mise` にリンクする |
| `scripts/install-skills.sh` | Claude CodeとCodexのskillsを、skills CLI（`pnpx skills add`）で入れ直す。`make skills` で実行する |
| `mise/config.toml` | すべてのMacで共通の設定 |
| `mise/config.personal.toml` | 私物Macだけの設定 |
| `mise/config.work.toml` | 仕事Macだけの設定。公開リポジトリなので社内ツールの名前などは書かない |
| `~/.config/mise/miserc.local.toml` | Macごとにenvを選ぶ。`scripts/bootstrap.sh` が最初に1回だけ書き、Git管理しない |
| `ssh/config` | SSHのホスト設定。`~/.ssh/config` からIncludeする |
| `.gitconfig` | `~/.gitconfig` にリンクする。Macごとの設定は `~/.gitconfig.local` と `~/.gitconfig.work` に書く。最後でincludeするので、共通の設定をMacごとに上書きできる。diffはdelta（`brew:git-delta`）で表示する |
| `git/ignore` | gitのグローバルなignore。gitが既定で読む `~/.config/git/ignore` にリンクする |
| `lazygit/config.yml` | `~/Library/Application Support/lazygit/config.yml` にリンクする。裏でのfetchはBitwardenの承認を毎回求めるので、`git.autoFetch` を止めている。diffはdeltaで表示する |
| `.zshrc` | `~/.zshrc` にリンクする。すべてのMacで共通。Macごとの設定は `~/.zshrc.local` に書く。最後に読み込むので、共通の設定を上書きできる。miseのactivateもここで行うので、`mise` はシェルからそのまま使える |
| `sheldon/plugins.toml` | zshのプラグイン。`~/.config/sheldon/plugins.toml` にリンクする。シェルの中で動くので、それぞれをタグかコミットに固定し、更新するときは固定を書き換える |
| `starship/starship.toml` | プロンプトの設定。`~/.config/starship.toml` にリンクする |
| `ghostty/config` | ターミナル（Ghostty）の設定。`~/.config/ghostty/config` にリンクする。使っているフォントはcaskで入れる |
| `.vimrc` | `~/.vimrc` にリンクする |
| `vscode/settings.json` / `vscode/keybindings.json` | VS Codeの設定。`~/Library/Application Support/Code/User/` にリンクする。Settings Syncは使わない。エディタのフォントはcaskで入れる |
| `claude/CLAUDE.md` | Claude Codeのグローバルな指示。`~/.claude/CLAUDE.md` にリンクする。`@~/.codex/AGENTS.md` で共通の指示を読み込み、Claude Codeだけのこと（AskUserQuestionの使い方）を足す |
| `claude/statusline.sh` | Claude Codeのステータスライン。`~/.claude/statusline.sh` にリンクする。jqを使う |
| `claude/keybindings.json` | Claude Codeのキーの割り当て。`~/.claude/keybindings.json` にリンクする |
| `claude/settings.json` | Claude Codeの設定のうち、すべてのMacで共通のキーだけ。Claude CodeやOrcaが書き換えるので、`~/.claude/settings.json` はリンクにせず、mise bootstrapがこのキーだけをマージする。権限の `allow`（その場で許可したもの）とOrcaのhooksは、Macごとのファイルに残す。`git push` は `ask` に入れ、Claude Codeが実行するたびに確認する |
| `codex/AGENTS.md` | Claude CodeとCodexで共通のグローバルな指示。`~/.codex/AGENTS.md` にリンクする。特定のツールにしかない機能の話は書かない |
| `codex/keybindings.json` | Codexのキーの割り当て。`~/.codex/keybindings.json` にリンクする |
| `codex/config.toml` | Codexの設定のうち `[desktop]` だけ。Codexがnotify・プラグイン・MCPサーバー（アプリの中のパス入り）を書くので、`~/.codex/config.toml` はリンクにせずマージする |
| `AGENTS.md` / `CLAUDE.md` | このリポジトリで作業するときの指示。中身は `AGENTS.md` に書き、`CLAUDE.md` は `@AGENTS.md` で読み込むだけ |

## AIの設定

- 指示は1つのファイルにまとめ、Claude Codeからは `@` で読み込む（Claude Codeの公式ドキュメントが勧める共有の仕方）。グローバルは `codex/AGENTS.md`、このリポジトリは直下の `AGENTS.md` に書く。Claude Codeだけのことは、それぞれの `CLAUDE.md` の読み込みの下に書く
- skillsは `scripts/install-skills.sh` に、入れ元のリポジトリをコミットに固定して並べる。新しくしたいときは、差分を読んでからコミットを書き換える。orca-cliはOrcaが自分で入れるので書かない
- 指示は短く保つ。Claude Codeは200行を超えると守られにくくなるとしていて、Codexは合計32KiBまでしか読まない。必ず止めたいことは指示ではなく `permissions.deny` やhookに書く
- Claude Codeの設定は `claude/` に置く。リポジトリ直下の `.claude/` は、このリポジトリ自体のプロジェクト設定として読まれてしまうため使わない
- `~/.claude/settings.json` の共通のキーを変えたら `claude/settings.json` にも反映する。マージは `claude/settings.json` にあるキーだけを見るので、そこから消したキーは各Macのファイルに残る
- 配列（`permissions.deny` や `permissions.ask` など）はマージせず、`claude/settings.json` の内容で丸ごと置き換わる
- `codex/config.toml` も同じくマージする。Codexの画面で `[desktop]` の設定を変えたら、`codex/config.toml` にも反映する
- Orcaはアプリ本体だけを、`scripts/bootstrap.sh` がstablyaiのtapのcask（`brew install --cask stablyai/orca/orca`）で入れる。miseの宣言にしないのは、外部のtapのcaskをmiseが読むにはRuby 3以上が要り、新しいMacにはないため（brewは同梱のRubyを使う）。手で入れたOrcaがあれば何もしない。Orcaは自分で更新する。設定はアプリの中（IndexedDBなど）にあり、ファイルとしては管理できない。`~/.orca/agent-hooks/` やClaude Codeのhooksは、Orcaが自分で入れる

## macOSの設定

- `mise/config.toml` の `[bootstrap.macos.defaults]` に書く。今の値は `defaults read <domain> <key>` で確かめられる
- システム設定で変えたら、`mise/config.toml` にも反映する。反映しないと、次の `mise bootstrap` で元に戻る
- `mise bootstrap` が書き換えたあとは、案内に従ってDockやFinderを再起動する（`killall Dock` など）
- アクセシビリティの設定（`com.apple.universalaccess`）は書かない。フルディスクアクセスのないターミナルからでは書き込めず、`mise bootstrap` が `failed to synchronize macOS preference domain com.apple.universalaccess` で止まるため。「新しいMac」の手順で手で設定する

## パッケージ

- 入れ方は3つに分ける
  - Homebrewのformula・cask、App Storeのアプリ: `[bootstrap.packages]` に `brew:` / `brew-cask:` / `mas:` で書く。`mise bootstrap` がbrewの代わりに、Homebrewの場所（/opt/homebrew）へ入れる
  - 言語の実行環境（node・python・rubyなど）: `[tools]` に書く。miseの場所に入る
  - miseで扱えないHomebrewのパッケージ: `scripts/bootstrap.sh` で `brew install` する。miseはHomebrewのAPIの情報をもとに自分で入れるので、APIに情報がない外部のtapのcask（Rubyの定義を評価するのにRuby 3以上が要る）は扱えない。今はOrcaだけ
- 新しく足すときは、まず `[bootstrap.packages]` に書いて `mise bootstrap --dry-run` で確かめ、miseで扱えなければ `scripts/bootstrap.sh` に回す。大きすぎて取得に失敗するcask（`font-biz-udgothic` や `font-google-sans-code` など、google/fontsを丸ごと取ってくるもの）は、別のものに替える。`brew info --cask --json=v2 <cask>` の `url` が `https://github.com/google/fonts.git` なら、それにあたる
- .pkgで入るcask（`google-drive` など）は、インストール中に管理者のパスワードを聞かれることがある
- kubectlは宣言しない。Docker Desktop（`brew-cask:docker-desktop`）が `/usr/local/bin/kubectl` に自分のものを置くので、それを使う（`.zshrc` の `kc` もこれを呼ぶ）
- 新しいMacでも必ず入れたいものだけを書く。アドホックに `brew install` したものは書かなくてよい
- 片方のMacでしか使わないものは、`mise/config.toml` ではなく `mise/config.personal.toml` か `mise/config.work.toml` に書く
- `mise bootstrap packages status --missing` で、宣言した項目が揃っているか確認できる
- `mise bootstrap packages prune --dry-run` で、宣言にないformulaを一覧できる。`--dry-run` を外すと実際に削除される
- 宣言にないcaskとApp Storeのアプリはpruneでは検出できない。`brew list --cask` と `mas list` を目で見る
- 手動でインストール済みのcaskは、`[bootstrap.brew] adopt = true` によりbrew管理下に取り込まれる

## 参考

- [mise bootstrapで私物Macと仕事Macの設定を管理する](https://blog.shibayu36.org/entry/2026/10/13/173000)（blog.shibayu36.org）
