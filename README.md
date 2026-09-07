# time-pulse — хук реального времени для ZCode

Простой bash-хук, который штампует актуальное время в контекст агента на каждом
старте сессии, сообщении пользователя и вызове инструмента. Без него модель
не знает, который час, и оценивает «сейчас» по данным обучения.

## Что делает

В контекст сессии попадает строка вида:

```
⏱ Сейчас: 2026-09-07 16:15:33 +0300 (MSK) · новая сессия · с прошлого сообщения: 5 мин 10 с
```

Три режима (один и тот же скрипт, разный аргумент):

| Режим    | Событие ZCode      | Что добавляет                                        |
|----------|--------------------|------------------------------------------------------|
| `session`| `SessionStart`     | время, причина старта (startup/resume/clear/compact), дельта с последнего сообщения |
| `prompt` | `UserPromptSubmit` | время, дельта с последнего сообщения                 |
| `tool`   | `PostToolUse`      | время, дельта с последнего вызова инструмента        |

Дельты считаются по файлам-меткам в `~/.cache/zcode-time/` — состояние переживает
перезапуск сессий, зависимостей нет.

## Требования

- bash, `date`, `jq` (для упаковки ответа в JSON)

## Установка

1. Положить скрипт и сделать исполняемым:

```bash
mkdir -p ~/.zcode/hooks
cp time-pulse.sh ~/.zcode/hooks/
chmod +x ~/.zcode/hooks/time-pulse.sh
```

2. Зарегистрировать в `~/.zcode/cli/config.json` — слить секцию `hooks`
   с уже имеющейся (если файла нет, создать с этим содержимым):

```json
{
  "hooks": {
    "enabled": true,
    "events": {
      "SessionStart": [
        { "hooks": [ { "type": "command", "command": "bash $HOME/.zcode/hooks/time-pulse.sh session", "timeout": 5 } ] }
      ],
      "UserPromptSubmit": [
        { "hooks": [ { "type": "command", "command": "bash $HOME/.zcode/hooks/time-pulse.sh prompt", "timeout": 5 } ] }
      ],
      "PostToolUse": [
        { "matcher": "Bash|Agent|WebFetch|WebSearch|mcp__", "hooks": [ { "type": "command", "command": "bash $HOME/.zcode/hooks/time-pulse.sh tool", "timeout": 5 } ] }
      ]
    }
  }
}
```

`matcher` у `PostToolUse` сужает срабатывание до событий, где время реально
полезно (shell, агенты, веб-запросы, MCP) — иначе контекст замусоривается
на каждом чтении файла.

3. Проверка вручную:

```bash
echo '{"source":"startup"}' | bash ~/.zcode/hooks/time-pulse.sh session
```

Должен напечататься JSON вида
`{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"⏱ …"}}`.

## Формат ответа

Скрипт печатает на stdout JSON с `hookSpecificOutput.additionalContext` —
текст попадает в контекст модели как служебная вставка перед ответом.
Ошибки и «неизвестный режим» уходят в stderr с ненулевым кодом выхода,
пустой stdin трактуется безопасно.
