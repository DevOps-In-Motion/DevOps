sudo useradd -r -s /bin/false -m -d /usr/share/ollama ollama
sudo mkdir -p /usr/share/ollama/.ollama/models
sudo chown -R ollama:ollama /usr/share/ollama