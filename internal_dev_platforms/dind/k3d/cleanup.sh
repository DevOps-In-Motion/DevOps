# Stop and remove the named container (or any using the image); frees 8080 and 8443
docker rm -f wiki-k3d-dind 2>/dev/null || true
for id in $(docker ps -aq --filter "ancestor=wiki-k3d-dind" 2>/dev/null); do docker rm -f "$id" 2>/dev/null; done