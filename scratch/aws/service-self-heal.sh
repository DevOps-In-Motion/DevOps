# Update service with self-healing config
sudo tee /etc/systemd/system/ollama.service > /dev/null <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=5
StartLimitInterval=0
MemoryLimit=14G
TimeoutStartSec=60
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama

# Add healthcheck script
sudo tee /usr/local/bin/ollama-healthcheck.sh > /dev/null <<'EOF'
#!/bin/bash
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:11434/api/tags --connect-timeout 5 --max-time 10)
if [ "$RESPONSE" != "200" ]; then
    echo "$(date): Ollama unhealthy, restarting..."
    systemctl restart ollama
fi
EOF

sudo chmod +x /usr/local/bin/ollama-healthcheck.sh

# Add to cron
(sudo crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/ollama-healthcheck.sh >> /var/log/ollama-healthcheck.log 2>&1") | sudo crontab -

echo "Self-healing configured!"