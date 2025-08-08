#!/bin/bash

echo "🚀 Запуск настройки всех сервисов..."

# Останавливаем все tmux сессии
echo "🔄 Останавливаем tmux сессии..."
tmux kill-session -t gensyn 2>/dev/null || true
tmux kill-session -t cysic 2>/dev/null || true
tmux kill-session -t dria 2>/dev/null || true
tmux kill-session -t dawn 2>/dev/null || true
tmux kill-session -t datagram 2>/dev/null || true

# Останавливаем старые сервисы
echo "🛑 Останавливаем старые сервисы..."
systemctl stop dria.service 2>/dev/null || true
systemctl stop cysic.service 2>/dev/null || true
systemctl stop datagram.service 2>/dev/null || true
systemctl stop dawn.service 2>/dev/null || true

# ═══════════════════ DRIA SERVICE ═══════════════════
echo "📡 Настройка Dria сервиса..."
sudo tee /etc/systemd/system/dria.service > /dev/null << 'DRIA_EOF'
[Unit]
Description=Dria Compute Launcher Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/bin/bash -c 'source ~/.bashrc && /root/.dria/bin/dkn-compute-launcher start'
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
DRIA_EOF

# ═══════════════════ CYSIC SERVICE ═══════════════════
echo "⚙️ Настройка Cysic сервиса..."
sudo tee /etc/systemd/system/cysic.service > /dev/null << 'CYSIC_EOF'
[Unit]
Description=Cysic Verifier Node
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/root/cysic-verifier
ExecStart=/bin/bash -c 'cd /root/cysic-verifier && bash start.sh'
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment="CUDA_VISIBLE_DEVICES="

[Install]
WantedBy=multi-user.target
CYSIC_EOF

# ═══════════════════ DATAGRAM SERVICE ═══════════════════
echo "📊 Настройка Datagram сервиса..."
sudo tee /etc/systemd/system/datagram.service > /dev/null << 'DATAGRAM_EOF'
[Unit]
Description=Datagram Node Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/bin/bash -c 'set -a; source /etc/environment; set +a && ./datagram-cli-x86_64-linux run -- -key "$DATAGRAM"'
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment="CUDA_VISIBLE_DEVICES="

[Install]
WantedBy=multi-user.target
DATAGRAM_EOF

# ═══════════════════ DAWN SERVICE ═══════════════════
echo "🌅 Настройка Dawn сервиса..."

# Проверяем существование папки Dawn
if [ ! -d "/root/The-Dawn-Bot" ]; then
    echo "❌ Папка /root/The-Dawn-Bot не найдена!"
    echo "Убедитесь, что Dawn Bot установлен в /root/The-Dawn-Bot"
    exit 1
fi

cd /root/The-Dawn-Bot

# Создаем виртуальное окружение если его нет
if [ ! -d "venv" ]; then
    echo "📦 Создание виртуального окружения для Dawn..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
fi

# Создаем auto_farm.py скрипт
cat > auto_farm.py << 'DAWN_SCRIPT_EOF'
import asyncio
import sys

from application import ApplicationManager
from utils import setup
from loader import config


def main():
    """Автоматический запуск Dawn Farm без интерактивного меню"""
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    setup()
    
    # Принудительно устанавливаем модуль FARM
    config.module = "farm"
    
    # Создаем экземпляр ApplicationManager
    app = ApplicationManager()
    
    # Запускаем инициализацию и основной процесс
    asyncio.run(run_farm_only(app))


async def run_farm_only(app: ApplicationManager):
    """Запуск только фарминга без показа меню"""
    await app.initialize()
    
    # Проверяем, что модуль farm существует
    if config.module not in app.module_map:
        print(f"❌ Модуль {config.module} не найден!")
        return
    
    # Загружаем прокси и аккаунты для фарминга
    from loader import proxy_manager
    proxy_manager.load_proxy(config.proxies)
    
    accounts, process_func = app.module_map[config.module]
    
    if not accounts:
        print("❌ Нет аккаунтов для фарминга!")
        return
    
    print(f"🌾 Запуск автоматического фарминга для {len(accounts)} аккаунтов...")
    
    # Запускаем бесконечный фарминг
    await app._farm_continuously(accounts)


if __name__ == "__main__":
    main()
DAWN_SCRIPT_EOF

chmod +x auto_farm.py

# Создаем Dawn systemd сервис
sudo tee /etc/systemd/system/dawn.service > /dev/null << 'DAWN_EOF'
[Unit]
Description=Dawn Farm Bot - Auto Mode
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/root/The-Dawn-Bot
ExecStart=/root/The-Dawn-Bot/venv/bin/python /root/The-Dawn-Bot/auto_farm.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="PYTHONPATH=/root/The-Dawn-Bot"
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
DAWN_EOF

# ═══════════════════ ЗАПУСК ВСЕХ СЕРВИСОВ ═══════════════════
echo "🔄 Перезагрузка systemd..."
systemctl daemon-reload

echo "✅ Включение и запуск всех сервисов..."
systemctl enable dria.service
systemctl enable cysic.service  
systemctl enable datagram.service
systemctl enable dawn.service

systemctl start dria.service
systemctl start cysic.service
systemctl start datagram.service  
systemctl start dawn.service

echo ""
echo "🎉 Все сервисы настроены и запущены!"
echo ""
echo "📊 Проверка статуса:"
echo "systemctl status dria.service"
echo "systemctl status cysic.service"
echo "systemctl status datagram.service"
echo "systemctl status dawn.service"
echo ""
echo "📋 Просмотр логов:"
echo "journalctl -u dria.service -f"
echo "journalctl -u cysic.service -f"
echo "journalctl -u datagram.service -f"
echo "journalctl -u dawn.service -f"
echo ""
echo "🔧 Управление сервисами:"
echo "systemctl stop/start/restart [service_name]"
