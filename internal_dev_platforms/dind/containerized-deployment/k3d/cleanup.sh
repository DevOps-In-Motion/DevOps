# Stop and remove wiki-k3d-dind container(s); frees 8080 and 8443.
# To free disk after "no space left on device": run this script, then on the host:
#   docker system prune -af
#   docker volume prune -f
# Then ensure host has 10GB+ free (df -h) and run ./testing/test-k3d.sh again.
docker system prune -af
docker volume prune -f
docker rm -f wiki-k3d-dind 2>/dev/null || true
for id in $(docker ps -aq --filter "ancestor=wiki-k3d-dind" 2>/dev/null); do docker rm -f "$id" 2>/dev/null; done