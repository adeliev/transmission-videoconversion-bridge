FROM lscr.io/linuxserver/transmission:latest

# Установка зависимостей для скрипта
RUN apk add --no-cache \
    ffmpeg \
    python3 \
    py3-requests \
    findutils

# Копирование скрипта внутрь образа не обязательно, так как мы можем примонтировать его,
# но для надежности можно и скопировать, если не хотите монтировать папку scripts.
# В данном случае мы будем монтировать папку scripts через docker-compose для удобства редактирования.

