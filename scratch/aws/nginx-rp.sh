sudo apt update
sudo apt install nginx -y

# Create nginx config
sudo tee /etc/nginx/sites-available/ollama > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;
    
    # Health check endpoint for API Gateway
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Ollama API endpoints
    location /api/ {
        proxy_pass http://127.0.0.1:11434/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        # Streaming support
        proxy_buffering off;
        proxy_cache off;
        
        # Timeouts for LLM responses
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/ollama /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

