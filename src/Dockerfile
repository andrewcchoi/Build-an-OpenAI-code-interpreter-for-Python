FROM python:3.12 AS builder

RUN pip install poetry==1.8.2

ENV POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_VIRTUALENVS_CREATE=1 \
    POETRY_CACHE_DIR=/tmp/poetry_cache

WORKDIR /src

COPY pyproject.toml poetry.lock ./

RUN poetry install --without dev --no-root && rm -rf $POETRY_CACHE_DIR

# The runtime image, used to just run the code provided its virtual environment
FROM python:3.12-slim AS runtime

ENV VIRTUAL_ENV=/src/.venv \
    PATH="/src/.venv/bin:$PATH"

WORKDIR /src

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}

COPY . .

# strip Windows line endings and set execute bit
RUN sed -i 's/\r$//' entrypoint.sh && chmod +x entrypoint.sh

# ensure /src/sample-data exists
RUN mkdir -p /src/sample-data

ENTRYPOINT ["./entrypoint.sh", "chat_app"]
