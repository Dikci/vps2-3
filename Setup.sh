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
echo ""
echo "🔧 Управление сервисами:"
echo "systemctl stop/start/restart [service_name]"
