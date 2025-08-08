#!/bin/bash

LOG_FILE="/var/log/monitoring.log"
LAST_CLEAR_FILE="/tmp/last_log_clear"

log() {
    local message="$1"
    echo "[$(date)] $message" | tee -a "$LOG_FILE"
}

clear_log_daily() {
    local now=$(date +%s)
    local last_clear=0

    [[ -f "$LAST_CLEAR_FILE" ]] && last_clear=$(cat "$LAST_CLEAR_FILE")

    if (( now - last_clear >= 86400 )); then
        log "🧹 Очистка лог-файла $LOG_FILE..."
        > "$LOG_FILE"
        echo "$now" > "$LAST_CLEAR_FILE"
        log "✅ Лог-файл очищен."
    fi
}

check_and_create_tmux_session_nexus() {
    log "🔍 Проверка nexus..."
    if ! tmux has-session -t nexus 2>/dev/null; then
        log "⚠️ Сессия tmux 'nexus' не найдена. Создаю новую..."
        tmux new-session -d -s nexus bash -c 'bash -c "set -a; . /etc/environment; set +a; docker stop nexus; docker rm nexus; docker run -it --init --name nexus nexusxyz/nexus-cli:latest start --node-id \$ID; exec bash"'
        log "✅ Сессия 'nexus' успешно создана и запущена."
    else
        log "✅ Сессия 'nexus' уже работает."
    fi
}

check_multiple_status() {
    log "🔍 Проверка Multiple..."

    # Пробуем выполнить status с таймаутом 260 секунд
    if ! timeout 260s bash -c 'cd ~/multipleforlinux && ./multiple-cli status' >/dev/null 2>&1; then
        log "❌ multiple-cli не отвечает или не найден. Выполняю переустановку..."

        rm -f ~/install.sh ~/update.sh ~/start.sh
        wget -q https://mdeck-download.s3.us-east-1.amazonaws.com/client/linux/install.sh
        source ./install.sh
        wget -q https://mdeck-download.s3.us-east-1.amazonaws.com/client/linux/update.sh
        source ./update.sh
        cd ~/multipleforlinux
        wget -q https://mdeck-download.s3.us-east-1.amazonaws.com/client/linux/start.sh
        source ./start.sh

        log "✅ Multiple успешно переустановлен и запущен."
    else
        log "✅ multiple-cli работает корректно."
    fi

    cd /root
}


check_docker_containers() {
    log "🔍 Проверка Docker-демона..."
    if ! systemctl is-active --quiet docker; then
        log "⚠️ Docker-демон не работает. Запускаю..."
        systemctl start docker
        sleep 5
        if ! systemctl is-active --quiet docker; then
            log "❌ Ошибка: не удалось запустить Docker-демон!"
            return
        fi
        log "✅ Docker-демон успешно запущен."
    fi

    log "🔍 Проверка Docker-контейнеров..."
    local non_up_containers
    non_up_containers=$(docker ps -a --filter "status=exited" --filter "status=created" --filter "status=paused" --format "{{.ID}} {{.Names}}")

    if [[ -n "$non_up_containers" ]]; then
        log "⚠️ Обнаружены остановленные контейнеры:"
        echo "$non_up_containers" | awk '{print $2}' | tee -a "$LOG_FILE"

        while IFS= read -r container; do
            local container_id container_name
            container_id=$(echo "$container" | awk '{print $1}')
            container_name=$(echo "$container" | awk '{print $2}')
            log "🔄 Перезапуск контейнера: $container_name..."
            docker restart "$container_id" >> "$LOG_FILE" 2>&1
            log "✅ Контейнер '$container_name' успешно перезапущен."
        done <<< "$non_up_containers"
    else
        log "✅ Все контейнеры работают."
    fi
}

check_services() {
    log "🔍 Проверка systemd-сервисов..."
    local services
    services=$(systemctl list-units --type=service --state=failed --no-pager --no-legend | awk '{print $1}' | grep -v '^●')

    if [[ -z "$services" ]]; then
        log "✅ Все сервисы работают нормально."
        return
    fi

    log "⚠️ Обнаружены неактивные сервисы:"
    log "$services"

    while read -r service; do
        [[ -z "$service" ]] && continue
        log "🔄 Перезапуск сервиса: $service..."
        systemctl restart "$service" >> "$LOG_FILE" 2>&1

        local new_status
        new_status=$(systemctl is-active "$service")
        if [[ "$new_status" == "active" ]]; then
            log "✅ Сервис '$service' успешно перезапущен."
        else
            log "❌ Ошибка: сервис '$service' не удалось запустить (новый статус: $new_status)."
        fi
    done <<< "$services"
}


while true; do
    log "🟢 Начало новой проверки..."
    clear_log_daily

    check_and_create_tmux_session_nexus
    check_multiple_status
    check_docker_containers
    check_services

    log "✅ Проверка завершена. Ожидание перед следующей проверкой..."
    sleep 3600
done
