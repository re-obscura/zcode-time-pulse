#!/usr/bin/env bash
# тесты time-pulse: изолированный кэш через XDG_CACHE_HOME, состояние сеется вручную.
# Запуск: bash test.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/time-pulse.sh"
total=0
fails=0
dirs=()

t() { # t "имя" "ожидаемо" "фактически"
  total=$((total + 1))
  if [[ "$2" == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: ожидалось [$2], получено [$3]"
    fails=$((fails + 1))
  fi
}

has() { [[ "$2" == *"$1"* ]] && echo yes || echo no; }
is_empty() { [[ -z "$1" ]] && echo yes || echo no; }
fresh() { local d; d=$(mktemp -d); dirs+=("$d"); echo "$d"; }
run() { local cache="$1"; shift; XDG_CACHE_HOME="$cache" bash "$script" "$@"; }
seed() { local cache="$1" file="$2" value="$3"; mkdir -p "$cache/zcode-time"; printf '%s' "$value" > "$cache/zcode-time/$file"; }

wds=(пн вт ср чт пт сб вс)
wd=${wds[$(date +%u)-1]}
today=$(date +%F)
yesterday=$(date -d yesterday +%F)
now=$(date +%s)

# --- session: валидный JSON, событие, дата, день недели, UTC ---
d=$(fresh); out=$(run "$d" session <<< '{"source":"startup"}'); rc=$?
t "session: exit 0" 0 "$rc"
t "session: событие SessionStart" SessionStart "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
t "session: локальная дата в штампе" yes "$(has "$today" "$out")"
t "session: день недели ($wd)" yes "$(has "$wd " "$out")"
t "session: UTC-время" yes "$(has "UTC $(date -u +%H:%M)" "$out")"
t "session: причина старта" yes "$(has 'новая сессия' "$out")"

# --- tool: первый замер печатает всегда ---
d=$(fresh); out=$(run "$d" tool); rc=$?
t "tool первый замер: exit 0" 0 "$rc"
t "tool первый замер: печатает" yes "$(has PostToolUse "$out")"

# --- tool: сразу повторно — тише порога, пустой stdout ---
out=$(run "$d" tool); rc=$?
t "tool тише порога: stdout пуст" yes "$(is_empty "$out")"
t "tool тише порога: exit 0" 0 "$rc"

# --- tool: порог прошёл — печатает ---
d=$(fresh); seed "$d" tool.emit "$((now - 301))"
out=$(run "$d" tool)
t "tool по порогу: печатает" yes "$(has PostToolUse "$out")"

# --- tool: поток коротких вызовов — порог считается от напечатанного штампа ---
d=$(fresh); seed "$d" tool.emit "$((now - 301))"; seed "$d" tool.last "$((now - 305))"
out=$(run "$d" tool)
t "поток коротких вызовов: печатает" yes "$(has PostToolUse "$out")"
t "дельта считается от последнего вызова" yes "$(has 'с прошлого инструмента: 5 мин' "$out")"

# --- tool: смена календарной даты прорывает порог ---
d=$(fresh); seed "$d" tool.emit "$((now - 10))"; seed "$d" tool.date "$yesterday"
out=$(run "$d" tool)
t "смена даты прорывает порог" yes "$(has PostToolUse "$out")"

# --- TIME_PULSE_TOOL_MIN=0: старое поведение, печатает каждый вызов ---
d=$(fresh); seed "$d" tool.emit "$now"; seed "$d" tool.date "$today"
out=$(XDG_CACHE_HOME="$d" TIME_PULSE_TOOL_MIN=0 bash "$script" tool)
t "TIME_PULSE_TOOL_MIN=0: печатает всегда" yes "$(has PostToolUse "$out")"

# --- мусор в TIME_PULSE_TOOL_MIN не роняет скрипт ---
d=$(fresh)
out=$(XDG_CACHE_HOME="$d" TIME_PULSE_TOOL_MIN=banana bash "$script" tool); rc=$?
t "мусорный TIME_PULSE_TOOL_MIN: exit 0" 0 "$rc"

# --- prompt: событие и человекочитаемая дельта ---
d=$(fresh); seed "$d" prompt.last "$((now - 90))"
out=$(run "$d" prompt)
t "prompt: событие UserPromptSubmit" UserPromptSubmit "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
t "prompt: дельта '1 мин …'" yes "$(has 'с прошлого сообщения: 1 мин' "$out")"

# --- tool: дельта в часах ---
d=$(fresh); seed "$d" tool.last "$((now - 7200))"
out=$(run "$d" tool)
t "tool: дельта '2 ч 0 мин'" yes "$(has '2 ч 0 мин' "$out")"

# --- UTC-ветка под другой таймзоной ---
d=$(fresh)
if [[ $(TZ=Pacific/Kiritimati date +%F) == "$(date -u +%F)" ]]; then
  want="UTC $(date -u +%H:%M)"
else
  want="UTC $(date -u +%F)"
fi
out=$(TZ=Pacific/Kiritimati XDG_CACHE_HOME="$d" bash "$script" tool)
t "UTC-ветка под TZ=Pacific/Kiritimati ('$want')" yes "$(has "$want" "$out")"

((${#dirs[@]})) && rm -rf "${dirs[@]}"
echo "итого: $total тестов, провалено: $fails"
exit $(( fails > 0 ))
