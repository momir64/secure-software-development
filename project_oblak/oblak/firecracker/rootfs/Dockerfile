FROM alpine:3.19

RUN apk add --no-cache python3 curl

# Install uv instead of pip for faster Python dependency management
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Runtime directory layout expected by the runner
RUN mkdir -p /var/runtime /var/task

# Bake in the trusted runner (read-only; user code cannot overwrite it)
COPY runner.py /var/runtime/runner.py
RUN chmod 544 /var/runtime/runner.py