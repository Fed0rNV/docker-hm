# ДЗ 3 - Docker

## Запуск

Нужны Docker с Compose и curl. Из папки проекта:

```sh
cp .env.example .env
docker compose up -d --build --wait --wait-timeout 120
```

Настройки в `.env`:

| Переменная | Что задаёт | По умолчанию в примере |
| --- | --- | --- |
| `GREETING` | Приветствие | `Hello from Fedor!` |
| `HOST_PORT` | Порт на компьютере | `8080` |

После изменения настроек выполнить `docker compose up -d`.
Внутри Compose приложение использует `STORAGE=redis` и
`REDIS_URL=redis://redis:6379/0`. Данные Redis сохраняются в volume `redis-data`.
На компьютере открыт только порт приложения.

## Запросы и остановка

Если порт изменён в `.env`, заменить 8080 в запросах.

```sh
curl -fsS http://127.0.0.1:8080/
curl -fsS -X POST http://127.0.0.1:8080/increment
docker compose logs
docker compose down
```

`down` сохраняет данные, а `down -v` удаляет их.

## Запуск с SQLite

Для уровня 6 используется отдельный файл:

```sh
docker compose -p hw6 -f compose.sqlite.yaml up -d --build --wait --wait-timeout 120
docker compose -p hw6 -f compose.sqlite.yaml down
```

На одном порту одновременно запускать только одну конфигурацию.

## Проверки

```sh
./scripts/run-all.sh
```

Команда проверяет уровни 4 и 6, затем два раза запускает `scripts/check.sh`.
Отдельный запуск полной проверки:

```sh
./scripts/check.sh
```

Команды и результаты проверок приведены в [REPORT.md](REPORT.md).
