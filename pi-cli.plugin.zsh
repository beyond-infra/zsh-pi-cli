# pi-cli — pi coding agent integrated into zsh.
#
# Ctrl+X → 🤖 agent mode: natural language → pi -p auto-executes
# Ctrl+G → 💡 suggest mode: natural language → pi translates to shell
#          command, puts it in the buffer for you to review and execute.
#
# Config (set in .zshrc before sourcing):
#   __PI_CLI_AGENT_PREFIX    — default: 🤖
#   __PI_CLI_SUGGEST_PREFIX  — default: 💡
#   __PI_CLI_AGENT_FLAGS     — default: --no-session --no-extensions --no-skills --no-context-files
#   __PI_CLI_SUGGEST_FLAGS   — default: --model haiku --no-tools --no-session --no-extensions --no-skills --no-context-files --thinking off

setopt nonomatch 2>/dev/null

# ── Agent mode ──────────────────────────────────────────────
typeset -g __PI_CLI_AGENT_PREFIX_CHAR
: "${__PI_CLI_AGENT_PREFIX_CHAR:="🤖"}"

typeset -g __PI_CLI_AGENT_PREFIX
: "${__PI_CLI_AGENT_PREFIX:="${__PI_CLI_AGENT_PREFIX_CHAR} "}"

typeset -g __PI_CLI_AGENT_FLAGS
: "${__PI_CLI_AGENT_FLAGS:=--no-session --no-extensions --no-skills --no-context-files}"

typeset -g __PI_CLI_AGENT_ACTIVE=0

# ── Suggest mode ────────────────────────────────────────────
typeset -g __PI_CLI_SUGGEST_PREFIX_CHAR
: "${__PI_CLI_SUGGEST_PREFIX_CHAR:="💡"}"

typeset -g __PI_CLI_SUGGEST_PREFIX
: "${__PI_CLI_SUGGEST_PREFIX:="${__PI_CLI_SUGGEST_PREFIX_CHAR} "}"

typeset -g __PI_CLI_SUGGEST_FLAGS
: "${__PI_CLI_SUGGEST_FLAGS:=--system-prompt '' --no-tools --no-session --no-extensions --no-skills --no-context-files --thinking off}"

typeset -g __PI_CLI_SUGGEST_ACTIVE=0

typeset -g __PI_CLI_WIDGETS_INSTALLED=0
typeset -g __PI_CLI_HAS_PREV_LINE_INIT=0
typeset -g __PI_CLI_HAS_PREV_LINE_PRE_REDRAW=0
typeset -g __PI_CLI_HAS_PREV_LINE_FINISH=0
typeset -g __PI_CLI_HAS_PREV_ACCEPT_LINE=0
typeset -gA __PI_CLI_GUARD_WIDGET_ALIASES=()

# ── Helpers ─────────────────────────────────────────────────

# Which prefix (if any) is currently active?
__pi_cli_active_prefix() {
  if (( __PI_CLI_AGENT_ACTIVE )); then
    print -r -- "${__PI_CLI_AGENT_PREFIX:-${__PI_CLI_AGENT_PREFIX_CHAR} }"
  elif (( __PI_CLI_SUGGEST_ACTIVE )); then
    print -r -- "${__PI_CLI_SUGGEST_PREFIX:-${__PI_CLI_SUGGEST_PREFIX_CHAR} }"
  else
    return 1
  fi
}

__pi_cli_prefix_active() {
  (( __PI_CLI_AGENT_ACTIVE || __PI_CLI_SUGGEST_ACTIVE ))
}

__pi_cli_prefix_len() {
  local p
  p=$(__pi_cli_active_prefix) || return 1
  print -r -- ${#p}
}

# ── command_not_found_handler (agent mode) ──────────────────

if (( $+functions[command_not_found_handler] )); then
  functions[__pi_cli_original_command_not_found_handler]=$functions[command_not_found_handler]
fi

command_not_found_handler() {
  emulate -L zsh

  local missing_command="$1"
  local -a cmd_with_args=("$@")

  shift
  local -a remaining_args=("$@")

  if [[ -z "$missing_command" ]]; then
    if (( $+functions[__pi_cli_original_command_not_found_handler] )); then
      __pi_cli_original_command_not_found_handler "${cmd_with_args[@]}"
      return $?
    fi
    return 127
  fi

  local agent_char="${__PI_CLI_AGENT_PREFIX_CHAR:-🤖}"

  if [[ "$missing_command" != "$agent_char" && "$missing_command" != ${agent_char}* ]]; then
    if (( $+functions[__pi_cli_original_command_not_found_handler] )); then
      __pi_cli_original_command_not_found_handler "${cmd_with_args[@]}"
      return $?
    fi
    print -u2 "zsh: command not found: ${missing_command}"
    return 127
  fi

  local -a effective_cmd=()

  if [[ "$missing_command" == "$agent_char" ]]; then
    effective_cmd=("${remaining_args[@]}")
  else
    local stripped="${missing_command#$agent_char}"
    if [[ -n "$stripped" ]]; then
      effective_cmd=("$stripped" "${remaining_args[@]}")
    else
      effective_cmd=("${remaining_args[@]}")
    fi
  fi

  if (( ${#effective_cmd[@]} == 0 )); then
    print -u2 "pi-cli: nothing to run after '${agent_char}'."
    return 127
  fi

  if ! command -v pi >/dev/null 2>&1; then
    print -u2 "pi: command not found."
    return 127
  fi

  local full_cmd
  full_cmd="$(printf '%q ' "${effective_cmd[@]}")"
  full_cmd="${full_cmd% }"

  local -a agent_flags
  [[ -n "$__PI_CLI_AGENT_FLAGS" ]] && agent_flags=(${=__PI_CLI_AGENT_FLAGS})
  bun /opt/homebrew/bin/pi "${agent_flags[@]}" -p "$full_cmd"
  return $?
}

# ── accept-line override (suggest mode) ─────────────────────

__pi_cli_accept_line() {
  emulate -L zsh

  if (( __PI_CLI_SUGGEST_ACTIVE )); then
    local suggest_prefix="${__PI_CLI_SUGGEST_PREFIX:-${__PI_CLI_SUGGEST_PREFIX_CHAR} }"
    local prompt="${BUFFER#$suggest_prefix}"

    # Build system info once, cached as a global
    if [[ -z "$__PI_CLI_SYSINFO" ]]; then
      typeset -g __PI_CLI_SYSINFO
      local brew_prefix=$(brew --prefix 2>/dev/null)
      [[ -z "$brew_prefix" ]] && brew_prefix=/opt/homebrew
      local -a parts=(
        "macOS $(sw_vers -productVersion 2>/dev/null) $(uname -m)"
        "zsh $ZSH_VERSION"
        "User: $USER"
        "Home: $HOME"
        "Brew: $brew_prefix"
        "Cwd: $PWD"
        "Node: $(node -v 2>/dev/null || echo none)"
        "Python: $(python3 -V 2>/dev/null | sed 's/Python //' || echo none)"
        "pip3: $(command -v pip3 2>/dev/null || echo none)"
        "uv: $(uv --version 2>/dev/null || echo none)"
        "Bun: $(bun --version 2>/dev/null || echo none)"
        "Go: $(go version 2>/dev/null | awk '{print $3}' || echo none)"
        "Rust: $(rustc --version 2>/dev/null | awk '{print $2}' || echo none)"
        "npm: $(command -v npm 2>/dev/null || echo none)"
        "yarn: $(command -v yarn 2>/dev/null || echo none)"
        "pnpm: $(command -v pnpm 2>/dev/null || echo none)"
        "Git: $(git --version 2>/dev/null | awk '{print $3}' || echo none)"
        "Docker: $(docker --version 2>/dev/null | awk -F'[ ,]' '{print $3}' || echo none)"
        "OrbStack: $(orbstack version 2>/dev/null || echo none)"
        "jq: $(command -v jq 2>/dev/null || echo none)"
        "fzf: $(command -v fzf 2>/dev/null || echo none)"
        "fd: $(command -v fd 2>/dev/null || echo none)"
        "rg: $(command -v rg 2>/dev/null || echo none)"
        "bat: $(command -v bat 2>/dev/null || echo none)"
        "eza: $(command -v eza 2>/dev/null || echo none)"
      )
      __PI_CLI_SYSINFO="System Info — ${(j:, :)parts}"
    fi

    print -n -- "\r\e[2K🤖 translating..."
    local result
    result=$(bun /opt/homebrew/bin/pi ${=__PI_CLI_SUGGEST_FLAGS} -p "Output exactly one zsh shell command. No explanation, no markdown, no backticks, no surrounding quotes. ${__PI_CLI_SYSINFO}. ${prompt}" 2>/dev/null)

    # Strip markdown fences and whitespace
    result="${result//\`\`\`*$'\n'/}"
    result="${result//\`\`\`/}"
    result="${result//\`/}"
    result="${result##$'\n'}"
    result="${result%%$'\n'}"
    result="${result## }"
    result="${result%% }"

    # Clear spinner line
    print -n -- $'\r\e[2K'

    if [[ -n "$result" ]]; then
      BUFFER="$result"
      CURSOR=${#BUFFER}
    fi
    __PI_CLI_SUGGEST_ACTIVE=0
    zle -R
    return
  fi

  if (( __PI_CLI_HAS_PREV_ACCEPT_LINE )); then
    zle __pi_cli_prev_accept_line
  else
    zle .accept-line
  fi
}

# ── Toggle widgets ──────────────────────────────────────────

__pi_cli_agent_toggle() {
  emulate -L zsh

  local agent_prefix="${__PI_CLI_AGENT_PREFIX:-${__PI_CLI_AGENT_PREFIX_CHAR} }"
  local suggest_prefix="${__PI_CLI_SUGGEST_PREFIX:-${__PI_CLI_SUGGEST_PREFIX_CHAR} }"

  if (( __PI_CLI_AGENT_ACTIVE )); then
    BUFFER="${BUFFER#$agent_prefix}"
    CURSOR=${#BUFFER}
    __PI_CLI_AGENT_ACTIVE=0
  else
    __PI_CLI_SUGGEST_ACTIVE=0
    BUFFER="${agent_prefix}"
    CURSOR=${#BUFFER}
    __PI_CLI_AGENT_ACTIVE=1
  fi
}

__pi_cli_suggest_toggle() {
  emulate -L zsh

  local suggest_prefix="${__PI_CLI_SUGGEST_PREFIX:-${__PI_CLI_SUGGEST_PREFIX_CHAR} }"
  local agent_prefix="${__PI_CLI_AGENT_PREFIX:-${__PI_CLI_AGENT_PREFIX_CHAR} }"

  if (( __PI_CLI_SUGGEST_ACTIVE )); then
    BUFFER="${BUFFER#$suggest_prefix}"
    CURSOR=${#BUFFER}
    __PI_CLI_SUGGEST_ACTIVE=0
  else
    __PI_CLI_AGENT_ACTIVE=0
    BUFFER="${suggest_prefix}"
    CURSOR=${#BUFFER}
    __PI_CLI_SUGGEST_ACTIVE=1
  fi
}

# ── ZLE hooks ───────────────────────────────────────────────

__pi_cli_line_init() {
  emulate -L zsh

  local prefix
  prefix=$(__pi_cli_active_prefix) && {
    BUFFER="${prefix}"
    CURSOR=${#prefix}
  }

  if (( __PI_CLI_HAS_PREV_LINE_INIT )); then
    zle __pi_cli_prev_line_init
  fi
}

__pi_cli_line_pre_redraw() {
  emulate -L zsh

  local plen
  plen=$(__pi_cli_prefix_len) && {
    if (( CURSOR < plen )); then
      CURSOR=$plen
    fi
    local blen=${#BUFFER}
    if (( CURSOR > blen )); then
      CURSOR=$blen
    fi
  }

  if (( __PI_CLI_HAS_PREV_LINE_PRE_REDRAW )); then
    zle __pi_cli_prev_line_pre_redraw
  fi
}

__pi_cli_line_finish() {
  emulate -L zsh

  __PI_CLI_AGENT_ACTIVE=0
  __PI_CLI_SUGGEST_ACTIVE=0

  if (( __PI_CLI_HAS_PREV_LINE_FINISH )); then
    zle __pi_cli_prev_line_finish
  fi
}

# ── Prefix guard ────────────────────────────────────────────

__pi_cli_guard_backward_action() {
  emulate -L zsh

  __pi_cli_prefix_active || {
    __pi_cli_call_guarded_original
    return
  }

  local prefix
  prefix=$(__pi_cli_active_prefix) || {
    __pi_cli_call_guarded_original
    return
  }

  if [[ "$BUFFER" == "$prefix"* ]] && (( CURSOR <= ${#prefix} )); then
    zle beep 2>/dev/null
    return
  fi

  __pi_cli_call_guarded_original
}

__pi_cli_call_guarded_original() {
  emulate -L zsh

  local alias="${__PI_CLI_GUARD_WIDGET_ALIASES[$WIDGET]-}"
  if [[ -n "$alias" ]]; then
    zle "$alias" 2>/dev/null
  else
    zle ".${WIDGET}" 2>/dev/null
  fi
}

__pi_cli_register_guard_widget() {
  emulate -L zsh

  local widget="$1"
  local alias="__pi_cli_prev_${widget//-/_}"

  if zle -A "$widget" "$alias" 2>/dev/null; then
    __PI_CLI_GUARD_WIDGET_ALIASES[$widget]="$alias"
  else
    __PI_CLI_GUARD_WIDGET_ALIASES[$widget]=""
  fi

  zle -N "$widget" __pi_cli_guard_backward_action
}

# ── Install ─────────────────────────────────────────────────

if [[ -o interactive ]]; then
  zle -N __pi_cli_agent_toggle
  zle -N __pi_cli_suggest_toggle
  zle -N __pi_cli_accept_line

  local -a __pi_cli_keymaps=("emacs" "viins")
  local keymap
  for keymap in "${__pi_cli_keymaps[@]}"; do
    bindkey -M "$keymap" '^X' __pi_cli_agent_toggle 2>/dev/null
    bindkey -M "$keymap" '^G' __pi_cli_suggest_toggle 2>/dev/null
  done
  unset keymap __pi_cli_keymaps

  if (( ! __PI_CLI_WIDGETS_INSTALLED )); then
    if zle -A zle-line-init __pi_cli_prev_line_init 2>/dev/null; then
      __PI_CLI_HAS_PREV_LINE_INIT=1
    fi
    zle -N zle-line-init __pi_cli_line_init

    if zle -A zle-line-pre-redraw __pi_cli_prev_line_pre_redraw 2>/dev/null; then
      __PI_CLI_HAS_PREV_LINE_PRE_REDRAW=1
    fi
    zle -N zle-line-pre-redraw __pi_cli_line_pre_redraw

    if zle -A zle-line-finish __pi_cli_prev_line_finish 2>/dev/null; then
      __PI_CLI_HAS_PREV_LINE_FINISH=1
    fi
    zle -N zle-line-finish __pi_cli_line_finish

    if zle -A accept-line __pi_cli_prev_accept_line 2>/dev/null; then
      __PI_CLI_HAS_PREV_ACCEPT_LINE=1
    fi
    zle -N accept-line __pi_cli_accept_line

    __pi_cli_register_guard_widget backward-delete-char
    __pi_cli_register_guard_widget backward-kill-word
    __pi_cli_register_guard_widget vi-backward-delete-char
    __pi_cli_register_guard_widget vi-backward-kill-word

    __PI_CLI_WIDGETS_INSTALLED=1
  fi
fi
