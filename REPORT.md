# Отчёт о проверках

## Реализовано

- Dockerfile с запуском от UID 10001.
- Compose для SQLite и отдельный Compose для приложения с Redis.
- Настраиваемые приветствие и внешний порт, `.env.example`.
- Именованные volumes, AOF Redis, healthcheck обоих сервисов.
- Read-only rootfs приложения, 256 MiB RAM и 1 CPU.
- Автопроверки уровней 4/6 и полный сценарий сохранения, сбоя и восстановления.
- Запись логов двух последовательных полных прогонов.

## Статус

Проверки выполнены 22 ноября 2026 года на macOS с Docker Desktop.
Команда `./scripts/run-all.sh` завершилась успешно: `ALL CHECKS PASSED`.
Уровни 4 и 6 проверены, затем полный сценарий выполнен два раза подряд.

Фактический вывод:

- [Уровни 4 и 6](reports/basics.log): `PASS: levels 4 and 6`.
- [Первый полный прогон](reports/check-1.log): `PASS: counter, persistence, outage, backup and restore verified`.
- [Второй полный прогон](reports/check-2.log): `PASS: counter, persistence, outage, backup and restore verified`.

## Результаты двух полных прогонов

| Проверка | Получено в обоих прогонах |
| --- | --- |
| Новое хранилище | count = 0 |
| Пять POST | count = 5 |
| Пересоздание app | count = 5 |
| down/up без удаления volumes | count = 5 |
| Redis остановлен | healthz = 200; readyz, GET /, POST /increment = 503 |
| Redis запущен снова | count = 5; следующий POST = 6 |
| Восстановление копии после удаления исходного volume | count = 6; следующий POST = 7 |
| Права процесса | UID = 10001 |
| Docker HostConfig | ReadonlyRootfs=true; Memory=268435456; NanoCpus=1000000000 |

Фактические HTTP-ответы, ограничения, команды Compose и логи приложения
печатаются проверочными скриптами и сохраняются при запуске run-all.
