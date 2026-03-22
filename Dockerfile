FROM ruby:3.2.6-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    postgresql-client \
    iputils-ping \
  && rm -rf /var/lib/apt/lists/*

ENV APP_HOME=/app
WORKDIR $APP_HOME

ENV BUNDLE_APP_CONFIG=.bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_PATH=vendor/bundle \
    BUNDLE_WITHOUT=development:test \
    RACK_ENV=production \
    LOG_NAMESPACE=ip_monitoring

COPY Gemfile Gemfile.lock* .ruby-version ./

RUN bundle config set --local deployment 'true' \
  && bundle config set --local without 'development test' \
  && bundle install

COPY . .

RUN useradd -m -u 1000 app \
  && chown -R app:app $APP_HOME \
  && chmod +x $APP_HOME/entrypoint.sh

USER app

ENTRYPOINT ["./entrypoint.sh"]

CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:4567", "config.ru"]

