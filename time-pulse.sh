#!/usr/bin/env bash
# time-pulse — штамп реального времени в контекст агента.
# Вызывается хуками ZCode с аргументом: session | prompt | tool.
# Печатает JSON с additionalContext, хранит время прошлого вызова в ~/.cache/zcode-time/.
set -euo pipefail

mode="${1:?usage: time-pulse.sh session|prompt|tool}"
dir="${XDG_CACHE_HOME:-$HOME/.cache}/zcode-time"
mkdir -p "$dir"

input=$(cat 2>/dev/null || true)
now_s=$(date +%s)
stamp=$(date '+%Y-%m-%d %H:%M:%S %z (%Z)')

emit() {
  jq -cn --arg e "$1" --arg c "$2" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
}

human_delta() {
  d=$1
  if   (( d < 0     )); then echo "0 с"
  elif (( d < 60    )); then echo "${d} с"
  elif (( d < 3600  )); then echo "$(( d / 60 )) мин $(( d % 60 )) с"
  elif (( d < 86400 )); then echo "$(( d / 3600 )) ч $(( (d % 3600) / 60 )) мин"
  else                   echo "$(( d / 86400 )) д $(( (d % 86400) / 3600 )) ч"
  fi
}

delta_for() {
  f="$dir/$1"
  if [[ -r "$f" ]] && last=$(cat "$f") 2>/dev/null; then
    human_delta $(( now_s - last ))
  else
    echo "первый замер"
  fi
}

case "$mode" in
  session)
    reason=$(printf '%s' "$input" | jq -r '.source // "?"' 2>/dev/null || echo '?')
    case "$reason" in
      startup) label="новая сессия" ;;
      resume)  label="сессия возобновлена" ;;
      clear)   label="контекст очищен" ;;
      compact) label="контекст сжат — это продолжение работы, не её начало" ;;
      *)       label="сессия (${reason})" ;;
    esac
    emit SessionStart "⏱ Сейчас: ${stamp} · ${label} · с прошлого сообщения: $(delta_for prompt.last)"
    printf '%s' "$now_s" > "$dir/session.last"
    ;;
  prompt)
    emit UserPromptSubmit "⏱ Сейчас: ${stamp} · с прошлого сообщения: $(delta_for prompt.last)"
    printf '%s' "$now_s" > "$dir/prompt.last"
    ;;
  tool)
    emit PostToolUse "⏱ ${stamp} · с прошлого инструмента: $(delta_for tool.last)"
    printf '%s' "$now_s" > "$dir/tool.last"
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 1
    ;;
esac
