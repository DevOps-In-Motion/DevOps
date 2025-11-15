#!/bin/bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y curl git
sudo apt install nginx -y
# generate log files
sudo touch /var/log/ollamalog-server.log
sudo touch /var/log/ollamalog-model.log


LLM_HOST="10.0.139.25"

# ssh to bastion host
ssh -A -i bastion-key.pem ubuntu@18.219.203.129

# From bastion, SSH to private instance
ssh ubuntu@10.0.139.25


wget https://github.com/ollama/ollama/releases/download/v0.12.10/ollama-linux-amd64.tgz
# On bastion - extract the archive
tar -xzf ollama-linux-amd64.tgz

# This should create an 'ollama' binary or directory
ls -lh

# If there's a directory called 'bin' or similar:
ls -lh bin/

# Find the ollama binary
find . -name "ollama" -type f

# Once you find it, transfer to private instance
# Assuming the binary is in current directory:
scp ./bin/ollama ubuntu@10.0.139.25:~/

# Still on bastion
scp ollama-linux-amd64 ubuntu@10.0.139.25:~/

# Verify transfer completed
ssh ubuntu@10.0.139.25 "ls -lh ~/ollama-linux-amd64"

# Install Ollama (best for your specs)
curl -fsSL https://ollama.com/install.sh | sh


### ------------------- LLM Host ------------------- ###
ssh ubuntu@10.0.139.25

sudo apt update
sudo apt install nginx -y

# On private instance
sudo apt update
sudo apt install nginx -y

# Configure Nginx as reverse proxy
sudo tee /etc/nginx/sites-available/ollama > /dev/null <<'EOF'
# Rate limiting zone
limit_req_zone $binary_remote_addr zone=ollama_limit:10m rate=10r/s;

upstream ollama_backend {
    server 127.0.0.1:11434;
    keepalive 32;
}

server {
    listen 8080;
    server_name _;

    # Rate limiting
    limit_req zone=ollama_limit burst=20 nodelay;
    
    # Request size limits
    client_max_body_size 10M;
    client_body_timeout 120s;
    
    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Logging
    access_log /var/log/nginx/ollama-access.log;
    error_log /var/log/nginx/ollama-error.log;
    
    location / {
        proxy_pass http://ollama_backend;
        proxy_http_version 1.1;
        
        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        
        # Disable buffering for streaming
        proxy_buffering off;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/ollama /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test config
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
sudo systemctl enable nginx

# 

# Verify installation
ollama --version

# Pull a model (choose based on RAM)
# For 16GB RAM:
ollama pull llama3.2:3b      # ~2GB, fast
# or
ollama pull mistral:7b       # ~4.1GB, better quality

# For 32GB RAM:
ollama pull llama3.1:8b      # ~4.7GB

# Start Ollama service (listens on 0.0.0.0:11434)
sudo systemctl enable ollama
sudo systemctl start ollama

# Test it works
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "Why is the sky blue?",
  "stream": false
}'