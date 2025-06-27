#!/bin/bash

LOG_FILE="/var/log/monitoring.log"
LAST_CLEAR_FILE="/tmp/last_log_clear"
GAIANET_PATH="/root/gaianet/bin/gaianet"

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

check_and_create_tmux_session_gensyn() {
    log "🔍 Проверка gensyn..."
    if ! tmux has-session -t gensyn 2>/dev/null; then
        log "⚠️ Сессия tmux 'gensyn' не найдена. Создаю новую..."
        tmux new-session -d -s gensyn "cd rl-swarm && ./run_rl_swarm.sh; bash"
        log "✅ Сессия 'gensyn' успешно создана и запущена."
    else
        log "✅ Сессия 'gensyn' уже работает."
    fi
}

check_and_create_tmux_session_nexus() {
    log "🔍 Проверка nexus..."
    if ! tmux has-session -t nexus 2>/dev/null; then
        log "⚠️ Сессия tmux 'nexus' не найдена. Создаю новую..."
        tmux new-session -d -s nexus "docker stop nexus && docker rm nexus && source /etc/environment && docker run -it --init --name nexus nexusxyz/nexus-cli:latest start --node-id $ID; bash"
        log "✅ Сессия 'nexus' успешно создана и запущена."
    else
        log "✅ Сессия 'nexus' уже работает."
    fi
}

check_and_create_tmux_session_datagram() {
    log "🔍 Проверка datagram..."
    if ! tmux has-session -t datagram 2>/dev/null; then
        log "⚠️ Сессия tmux 'datagram' не найдена. Создаю новую..."
        tmux new-session -d -s datagram "source /etc/environment && ./datagram-cli-x86_64-linux run -- -key $DATAGRAM; bash"
        log "✅ Сессия 'datagram' успешно создана и запущена."
    else
        log "✅ Сессия 'datagram' уже работает."
    fi
}

check_and_create_tmux_session_dawn() {
    log "🔍 Проверка dawn..."
    if ! tmux has-session -t dawn 2>/dev/null; then
        log "⚠️ Сессия tmux 'dawn' не найдена. Создаю новую..."
        tmux new-session -d -s dawn "cd The-Dawn-Bot && python3 -m venv venv && source venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt && python run.py; bash"
        log "✅ Сессия 'dawn' успешно создана и запущена."
    else
        log "✅ Сессия 'dawn' уже работает."
    fi
}

check_and_create_tmux_session_dria() {
    log "🔍 Проверка dria..."
    if ! tmux has-session -t dria 2>/dev/null; then
        log "⚠️ Сессия tmux 'dria' не найдена. Создаю новую..."
        tmux new-session -d -s dria "/root/.dria/bin/dkn-compute-launcher start; bash"
        log "✅ Сессия tmux 'dria' успешно создана."
    else
        log "✅ Сессия tmux 'dria' уже работает."
    fi
}

check_multiple_status() {
    log "🔍 Проверка Multiple..."
    cd ~/multipleforlinux || { log "❌ Ошибка: не удалось перейти в ~/multipleforlinux"; return; }

    local status_output
    status_output=$(timeout 60s ./multiple-cli status)

    if [[ $? -eq 124 ]]; then
        log "❌ Ошибка: multiple-cli status не завершился за 60 сек."
        return
    fi

    if [[ $status_output != *"Node Statistical"* ]]; then
        log "⚠️ multiple-node не работает. Перезапускаю..."
        nohup ./multiple-node > output.log 2>&1 &
        log "✅ multiple-node был успешно запущен."
    else
        log "✅ multiple-node работает нормально."
    fi
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

check_gaianet_node() {
    log "🔍 Проверка gaianet (порт 8080)..."

    if ! nc -z localhost 8080 >/dev/null 2>&1; then
        log "⚠️ Сервис gaias на порту 8080 недоступен. Перезапускаю gaianet..."

        log "🔄 Остановка gaianet..."
        $GAIANET_PATH stop >> "$LOG_FILE" 2>&1 || log "❌ Ошибка при остановке gaianet."

        sleep 2

        log "🔄 Запуск gaianet..."
        $GAIANET_PATH start >> "$LOG_FILE" 2>&1 || log "❌ Ошибка при запуске gaianet."

        if nc -z localhost 8080 >/dev/null 2>&1; then
            log "✅ gaianet успешно перезапущен."
        else
            log "❌ Ошибка: gaianet не удалось перезапустить."
        fi
    else
        log "✅ Сервис gaias на порту 8080 работает нормально."
    fi
}

while true; do
    log "🟢 Начало новой проверки..."
    clear_log_daily

    check_and_create_tmux_session_dria
    check_and_create_tmux_session_gensyn
    check_and_create_tmux_session_nexus
    check_and_create_tmux_session_datagram
    check_and_create_tmux_session_dawn
    check_multiple_status
    check_docker_containers
    check_services
    check_gaianet_node

    log "✅ Проверка завершена. Ожидание перед следующей проверкой..."
    sleep 250
done
