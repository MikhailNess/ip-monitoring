# IP Monitoring (тестовое задание)

Небольшой JSON API на Sinatra для учёта IP-адресов и периодической ICMP-проверки доступности. Результаты пингов пишутся в PostgreSQL; по окну времени можно запросить агрегированную статистику (RTT, потери).

Отдельный процесс-воркер в цикле обходит **активные** на текущий момент IP (с открытым периодом мониторинга) и для каждого вызывает системный `ping`. API и воркер используют общую БД и слой сервисов/репозитория на Sequel.

## Стек

- **Ruby** 3.2.x (см. `.ruby-version`)
- **Sinatra** + **Puma**
- **Sequel** + **pg** (PostgreSQL)
- Валидация входа: **dry-validation**
- Тесты: **RSpec**, **rack-test**
- Статический анализ: **RuboCop**
- **Docker** / **Docker Compose** (приложение, БД, воркер, прогон тестов)

## Требования

- [Docker](https://docs.docker.com/get-docker/) и [Docker Compose](https://docs.docker.com/compose/) v2

## Быстрый старт (Docker Compose)

Склонируйте репозиторий (подставьте свой `OWNER` и при необходимости имя репозитория; URL — из **Code** на GitHub):

```bash
git clone https://github.com/OWNER/monitoring.git
cd monitoring

docker compose up --build
```

Сервисы:

- **app** — API на хосте **4567** (`http://localhost:4567`). Перед стартом entrypoint ждёт БД и выполняет `rake db:migrate` (только при `ROLE=app`).
- **worker** — цикл ICMP-пингов (`workers/ping_worker.rb`); интервал и таймаут задаются в `docker-compose.yml` (`CHECK_INTERVAL_SECONDS`, `PING_TIMEOUT_SECONDS`, `LOG_LEVEL` и др.).
- **db** — PostgreSQL 15 (данные в tmpfs у сервиса `db`, после перезапуска контейнера БД пустая).

Корень `GET /` редиректит на **`/demo`** — статическую страницу (`public/demo.html` + `demo.css` / `demo.js`): формы дергают API через `fetch`. Для проверок из скриптов удобен `curl` к `http://localhost:4567`.

## Переменные окружения

В **docker-compose.yml** уже заданы строка подключения к БД, `ROLE`, `RACK_ENV` и параметры воркера. Менять удобно через `environment` у сервисов или через [env-файл Compose](https://docs.docker.com/compose/environment-variables/set-environment-variables/).

Ориентир по именам переменных (пример заполнения — `.env.example`):

| Переменная | Назначение |
|------------|------------|
| `DATABASE_URL` | подключение к PostgreSQL (обязательно для приложения и воркера) |
| `RACK_ENV` | окружение приложения (`production` в образах из compose) |
| `DB_POOL`, `DB_POOL_TIMEOUT` | пул подключений Sequel |
| `CHECK_INTERVAL_SECONDS`, `PING_TIMEOUT_SECONDS` | воркер |
| `LOG_NAMESPACE` | префикс в JSON-логах entrypoint |
| `ROLE` | `app` или `worker` — у `app` после ожидания БД выполняются миграции (`entrypoint.sh`) |

## API (кратко)

Все ответы по маршрутам `/ips` — JSON. Параметры запросов приходят как у обычного Rack/Sinatra (в тестах используется form/url-encoded).

| Метод | Путь | Описание |
|--------|------|----------|
| `POST` | `/ips` | Создание IP. Тело: `ip` (IPv4/IPv6), `enabled` (boolean). Ответ `201` с `id`, `ip`, `enabled`. Дубликат активного IP — `409`. |
| `POST` | `/ips/:id/enable` | Включить мониторинг (открыть период активности). |
| `POST` | `/ips/:id/disable` | Выключить мониторинг. |
| `GET` | `/ips/:id/stats` | Статистика за период: query `time_from`, `time_to` (ISO8601). `422`, если в окне нет ни одной учтённой проверки (см. `app/repositories/sql/ip_stats.sql`). |
| `DELETE` | `/ips/:id` | Мягкое удаление IP (`204`). |

Коды ошибок и формат тел смотрите в `app/api/error_responses.rb` и обработчиках в `app/api/app.rb`.

## Сценарий использования

Типичный проход «появились замеры → можно смотреть статистику». Его можно выполнить **в браузере** (`http://localhost:4567/demo` при поднятом `docker compose`) или **через `curl`** — шаги ниже на уровне API:

1. **Создать IP и включить мониторинг** — либо сразу `enabled=true`, либо после создания вызвать `POST /ips/:id/enable`. Пока период мониторинга закрыт, воркер этот адрес не пингует.
2. **Воркер** — при `docker compose up` уже запущен сервис `worker` (тот же `DATABASE_URL`, что у `app`).
3. **Подождать 1–2 цикла воркера** — длительность цикла задаётся `CHECK_INTERVAL_SECONDS` в `docker-compose.yml` (по умолчанию 60 с). За это время в БД должны появиться строки в `ip_checks`.
4. **Запросить статистику** — `GET /ips/:id/stats` с `time_from` и `time_to` в ISO8601 (UTC), чтобы окно перекрывало моменты проверок и активный период мониторинга. Если в выборке нет ни одной проверки, будет `422` (даже при «плохих» пингах статистика может вернуться с `loss_percent` и пустыми RTT).

Пример (подставьте `id`; `time_from` / `time_to` — ISO8601 в UTC, интервал должен пересекаться с моментами проверок):

```bash
BASE=http://localhost:4567

curl -s -X POST "$BASE/ips" -d 'ip=127.0.0.1' -d 'enabled=true'
# из ответа возьмите id, например 1

curl -sG "$BASE/ips/1/stats" \
  --data-urlencode "time_from=2026-01-01T12:00:00Z" \
  --data-urlencode "time_to=2026-01-01T13:00:00Z"
```

## Тесты и CI

Тесты в Docker (миграции и очистка таблиц — как в `spec/spec_helper.rb`):

```bash
docker compose -f docker-compose.test.yml run --rm test
```

GitHub Actions (`.github/workflows/ci.yml`): на push/PR в ветку `main` последовательно запускаются **RuboCop** и **RSpec** с сервисом PostgreSQL 15.

## Структура проекта (ориентир)

- `app/api/app.rb` — маршруты Sinatra
- `app/services/` — бизнес-логика (создание IP, enable/disable, статистика, пинг)
- `app/repositories/` — доступ к данным Sequel
- `app/validators/` — dry-validation контракты
- `migrations/` — миграции Sequel
- `public/` — статика демо (`demo.html`, `demo.css`, `demo.js`)
- `workers/ping_worker.rb` — фоновый цикл проверок

## Ограничения

- Парсинг вывода `ping` зависит от формата системы (локаль, ОС, конкретная реализация утилиты).
- Нет аутентификации — это тестовый сервис.
- Нет rate limiting.
- Воркер обходит IP **последовательно**, без параллелизма по адресам.
