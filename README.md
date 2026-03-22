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

## Требования для локального запуска

- Ruby и Bundler
- PostgreSQL 15+ (или только Docker — см. ниже)
- Для воркера на хосте: утилита `ping` (в Debian/Ubuntu пакет `iputils-ping`)

## Быстрый старт: локально

```bash
git clone <url-репозитория> monitoring
cd monitoring

bundle install

cp .env.example .env
# Отредактируйте DATABASE_URL под свой PostgreSQL (хост, порт, пользователь, БД, пароль).
```

Поднимите PostgreSQL и создайте БД/пользователя, если их ещё нет. Пример строки подключения см. в `.env.example`.

```bash
bundle exec rake db:migrate

bundle exec puma -b tcp://0.0.0.0:4567 config.ru
```

Сервер по умолчанию слушает порт **4567**. Корень `GET /` редиректит на **`/demo`** — статическую страницу (`public/demo.html` + `demo.css` / `demo.js`): формы и кнопки вызывают то же API через `fetch`, ответы показываются на странице. Это удобно для ручной проверки без терминала; для скриптов и CI по-прежнему уместны `curl` и другие клиенты.

### Воркер пинга (отдельный терминал)

Интервал и таймаут задаются переменными окружения (см. `.env.example`):

- `CHECK_INTERVAL_SECONDS` — пауза между циклами обхода (по умолчанию задано `60`)
- `PING_TIMEOUT_SECONDS` — таймаут одного пинга
- `LOG_LEVEL` — уровень логов (`Logger`)

```bash
# из корня проекта, с тем же DATABASE_URL, что и у API
bundle exec ruby workers/ping_worker.rb
```

## Быстрый старт: Docker Compose

```bash
docker compose up --build
```

- **app** — API на порту `4567`, перед стартом entrypoint ждёт БД и выполняет `rake db:migrate` (только при `ROLE=app`).
- **worker** — цикл пингов (`workers/ping_worker.rb`).
- **db** — PostgreSQL 15 (данные в tmpfs, после перезапуска контейнера БД пустая).

Прогон тестов в Compose (отдельный compose-файл):

```bash
docker compose -f docker-compose.test.yml run --rm test
```

## Переменные окружения

Обязательная для приложения и воркера: **`DATABASE_URL`**.

Часто используемые (см. также `.env.example`):

| Переменная | Назначение |
|------------|------------|
| `RACK_ENV` | `development` / `test` / `production` |
| `DB_POOL`, `DB_POOL_TIMEOUT` | пул подключений Sequel |
| `CHECK_INTERVAL_SECONDS`, `PING_TIMEOUT_SECONDS` | воркер |
| `LOG_NAMESPACE` | префикс в JSON-логах entrypoint |
| `ROLE` | `app` или `worker` — влияет на прогон миграций в `entrypoint.sh` |

В `development` подхватывается `.env` через `dotenv` (`config/environment.rb`).

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

Типичный проход «появились замеры → можно смотреть статистику». Его можно выполнить **в браузере** (`http://localhost:4567/demo` при локальном запуске или тот же путь на хосте при Docker) или **из терминала** — шаги ниже описывают поток на уровне API:

1. **Создать IP и включить мониторинг** — либо сразу `enabled=true`, либо после создания вызвать `POST /ips/:id/enable`. Пока период мониторинга закрыт, воркер этот адрес не пингует.
2. **Запустить воркер** — отдельный процесс (`bundle exec ruby workers/ping_worker.rb` или сервис `worker` в Docker Compose), с тем же `DATABASE_URL`, что и у API.
3. **Подождать 1–2 цикла воркера** — длительность цикла задаётся `CHECK_INTERVAL_SECONDS` (в `docker-compose.yml` у `worker` по умолчанию 60 с; локально без Compose см. `.env` и дефолт в `workers/ping_worker.rb`). За это время в БД должны появиться строки в `ip_checks`.
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

```bash
# Нужна доступная БД; RSpec сам применит миграции и перед каждым request-тестом очистит таблицы.
export RACK_ENV=test
export DATABASE_URL=postgres://user:pass@localhost:5432/monitoring_test
bundle exec rspec
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
