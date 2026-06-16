# Fallback to pi coding agent when a command is not found.
#
# Press Ctrl+G to toggle 🤖 prefix mode.
# Type your coding task, press Enter — it runs `pi --provider google -p "your request"`.
# Press Ctrl+G again to go back to normal mode.
#
# Config (set in .zshrc before sourcing):
#   __PI_CLI_PREFIX   — default: 🤖

typeset -g __PI_CLI_PREFIX_CHAR
: "${__PI_CLI_PREFIX_CHAR:="🤖"}"

typeset -g __PI_CLI_PREFIX
: "${__PI_CLI_PREFIX:="${__PI_CLI_PREFIX_CHAR} "}"

typeset -g __PI_CLI_PREFIX_ACTIVE=0
typeset -g __PI_CLI_WIDGETS_INSTALLED=0
typeset -g __PI_CLI_HAS_PREV_LINE_INIT=0
typeset -g __PI_CLI_HAS_PREV_LINE_PRE_REDRAW=0
typeset -g __PI_CLI_HAS_PREV_LINE_FINISH=0
typeset -gA __PI_CLI_GUARD_WIDGET_ALIASES=()

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

  local prefix_char="${__PI_CLI_PREFIX_CHAR:-🤖}"

  local handled=false
  local -a effective_cmd=()

  if [[ "$missing_command" == "$prefix_char" ]]; then
    handled=true
    effective_cmd=("${remaining_args[@]}")
  elif [[ "$missing_command" == ${prefix_char}* ]]; then
    handled=true
    local stripped="${missing_command#$prefix_char}"
    if [[ -n "$stripped" ]]; then
      effective_cmd=("$stripped" "${remaining_args[@]}")
    else
      effective_cmd=("${remaining_args[@]}")
    fi
  fi

  if [[ "$handled" != true ]]; then
    if (( $+functions[__pi_cli_original_command_not_found_handler] )); then
      __pi_cli_original_command_not_found_handler "${cmd_with_args[@]}"
      return $?
    fi
    print -u2 "zsh: command not found: ${missing_command}"
    return 127
  fi

  if (( ${#effective_cmd[@]} == 0 )); then
    print -u2 "pi-cli: nothing to run after prefix."
    return 127
  fi

  if ! command -v pi >/dev/null 2>&1; then
    if (( $+functions[__pi_cli_original_command_not_found_handler] )); then
      __pi_cli_original_command_not_found_handler "${cmd_with_args[@]}"
      return $?
    fi
    print -u2 "pi: command not found."
    return 127
  fi

  local full_cmd
  full_cmd="$(printf '%q ' "${effective_cmd[@]}")"
  full_cmd="${full_cmd% }"

  pi --provider google -p "$full_cmd"
  return $?
}

__pi_cli_toggle_prefix() {
  emulate -L zsh

  local prefix="${__PI_CLI_PREFIX:-${__PI_CLI_PREFIX_CHAR} }"
  local prefix_len=${#prefix}

  if [[ "$BUFFER" == "$prefix"* ]]; then
    BUFFER="${BUFFER#$prefix}"
    if (( CURSOR > prefix_len )); then
      CURSOR=$(( CURSOR - prefix_len ))
    else
      CURSOR=0
    fi
    __PI_CLI_PREFIX_ACTIVE=0
  else
    BUFFER="${prefix}${BUFFER}"
    CURSOR=$(( CURSOR + prefix_len ))
    __PI_CLI_PREFIX_ACTIVE=1
  fi
}

__pi_cli_line_init() {
  emulate -L zsh

  if (( __PI_CLI_PREFIX_ACTIVE )); then
    local prefix="${__PI_CLI_PREFIX:-${__PI_CLI_PREFIX_CHAR} }"
    BUFFER="${prefix}"
    CURSOR=${#prefix}
  fi

  if (( __PI_CLI_HAS_PREV_LINE_INIT )); then
    zle __pi_cli_prev_line_init
  fi
}

__pi_cli_line_pre_redraw() {
  emulate -L zsh

  if (( __PI_CLI_PREFIX_ACTIVE )); then
    local prefix="${__PI_CLI_PREFIX:-${__PI_CLI_PREFIX_CHAR} }"
    local prefix_len=${#prefix}

    if (( CURSOR < prefix_len )); then
      CURSOR=$prefix_len
    fi

    local buffer_len=${#BUFFER}
    if (( CURSOR > buffer_len )); then
      CURSOR=$buffer_len
    fi
  fi

  if (( __PI_CLI_HAS_PREV_LINE_PRE_REDRAW )); then
    zle __pi_cli_prev_line_pre_redraw
  fi
}

__pi_cli_line_finish() {
  emulate -L zsh

  if (( __PI_CLI_HAS_PREV_LINE_FINISH )); then
    zle __pi_cli_prev_line_finish
  fi
}

__pi_cli_guard_backward_action() {
  emulate -L zsh

  if (( ! __PI_CLI_PREFIX_ACTIVE )); then
    __pi_cli_call_guarded_original
    return
  fi

  local prefix="${__PI_CLI_PREFIX:-${__PI_CLI_PREFIX_CHAR} }"
  local prefix_len=${#prefix}

  if [[ "$BUFFER" == "$prefix"* ]] && (( CURSOR <= prefix_len )); then
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

if [[ -o interactive ]]; then
  zle -N __pi_cli_toggle_prefix

  local -a __pi_cli_keymaps=("emacs" "viins")
  local keymap
  for keymap in "${__pi_cli_keymaps[@]}"; do
    bindkey -M "$keymap" '^G' __pi_cli_toggle_prefix 2>/dev/null
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

    __pi_cli_register_guard_widget backward-delete-char
    __pi_cli_register_guard_widget backward-kill-word
    __pi_cli_register_guard_widget vi-backward-delete-char
    __pi_cli_register_guard_widget vi-backward-kill-word

    __PI_CLI_WIDGETS_INSTALLED=1
  fi
fi
