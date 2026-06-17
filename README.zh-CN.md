# zsh-pi-cli

[English](README.md)

将 pi 编码智能体集成到 zsh 中，通过快捷键提供两种模式：

<img src="assets/readme-demo.gif" alt="zsh-pi-cli demo" width="960" />

- **Ctrl+X** `🤖` — 智能体模式：输入需求，pi 直接执行
- **Ctrl+G** `💡` — 建议模式：用自然语言描述，pi 翻译为 shell 命令供你确认后执行

两种模式均在执行一次后自动退出。

## 安装

通过 [Sheldon](https://sheldon.community/) 安装：

```toml
[plugins.pi-cli]
github = "beyond-infra/zsh-pi-cli"
use = ["pi-cli.plugin.zsh"]
```

或手动安装：

```zsh
source /path/to/pi-cli.plugin.zsh
```

需要已安装 `pi` CLI 和 `bun`。

## 配置

在 `.zshrc` 中 source 之前设置：

```zsh
export __PI_CLI_AGENT_FLAGS="--model sonnet --no-session --no-extensions --no-skills --no-context-files"
export __PI_CLI_SUGGEST_FLAGS="--system-prompt '' --no-tools --no-session --no-extensions --no-skills --no-context-files --thinking off"
```

建议模式会自动检测可用工具（node、python、uv、bun、go、rust、docker 等）并传递系统信息给 pi，以生成准确的命令。
