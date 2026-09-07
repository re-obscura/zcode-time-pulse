#!/usr/bin/env bash
# time-pulse — штамп реального времени в контекст агента.
# Вызывается хуками ZCode с аргументом: session | prompt | tool.
# Печатает JSON с additionalContext, хранит время прошлого вызова в ~/.cache/zcode-time/.
set -euo pipefail

mode="${1:?usage: time-pulse.sh session|prompt|tool}"
dir="${XDG_CACHE_HOME:-$HOME/.cache}/zcode-time"
mkdir -p "$dir"

# tool-штамп не печатается, пока с предыдущего напечатанного не прошло tool_min секунд; 0 = всегда
tool_min="${TIME_PULSE_TOOL_MIN:-300}"
[[ "$tool_min" =~ ^[0-9]+$ ]] || tool_min=300

input=$(cat 2>/dev/null || true)
now_s=$(date +%s)

wds=(пн вт ср чт пт сб вс)
stamp="$(date '+%Y-%m-%d') ${wds[$(date +%u)-1]} $(date '+%H:%M:%S %z (%Z)')"
if [[ $(date -u +%F) == "$(date +%F)" ]]; then
  stamp+=" · UTC $(date -u +%H:%M)"
else
  # UTC-дата отличается от локальной (ночь, другие таймзоны) — показываем целиком
  stamp+=" · UTC $(date -u '+%F %H:%M')"
fi

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

# порог считается от последнего напечатанного штампа, а не последнего вызова —
# иначе при потоке коротких вызовов порог не наступает никогда и штампы вымирают
tool_due() {
  [[ -r "$dir/tool.emit" ]] || return 0
  local last
  last=$(cat "$dir/tool.emit")
  (( now_s - last >= tool_min )) && return 0
  [[ "$(cat "$dir/tool.date" 2>/dev/null || true)" != "$(date +%F)" ]] && return 0
  return 1
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
    delta=$(delta_for tool.last)
    printf '%s' "$now_s" > "$dir/tool.last"
    if tool_due; then
      emit PostToolUse "⏱ ${stamp} · с прошлого инструмента: ${delta}"
      printf '%s' "$now_s" > "$dir/tool.emit"
      date +%F > "$dir/tool.date"
    fi
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 1
    ;;
esac
