# zsh-pi-cli

pi coding agent integrated into zsh. Two modes via keybindings:

<img src="assets/readme-demo.gif" alt="zsh-pi-cli demo" width="960" />

- **Ctrl+X** `🤖` — agent mode: type a request, pi executes it directly
- **Ctrl+G** `💡` — suggest mode: type natural language, pi translates to a shell command you review first

Both modes auto-exit after one execution.

## Install

Via [Sheldon](https://sheldon.community/):

```toml
[plugins.pi-cli]
github = "beyond-infra/zsh-pi-cli"
use = ["pi-cli.plugin.zsh"]
```

Or manually:

```zsh
source /path/to/pi-cli.plugin.zsh
```

Requires `pi` CLI and `bun` installed.

## Config

Set in `.zshrc` before sourcing:

```zsh
export __PI_CLI_AGENT_FLAGS="--model sonnet --no-session --no-extensions --no-skills --no-context-files"
export __PI_CLI_SUGGEST_FLAGS="--system-prompt '' --no-tools --no-session --no-extensions --no-skills --no-context-files --thinking off"
```

Suggest mode auto-detects available tools (node, python, uv, bun, go, rust, docker, etc.) and passes system info to pi for accurate command generation.
