#!/bin/bash

echo "Testing Ollama API /api/tags endpoint..."
TAGS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/tags)
if [[ "$TAGS_RESPONSE" == "200" ]]; then
  echo "✅ /api/tags endpoint reachable (HTTP 200)"
else
  echo "❌ /api/tags endpoint returned HTTP $TAGS_RESPONSE"
fi

echo
echo "Testing health endpoint /health..."
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health)
if [[ "$HEALTH_RESPONSE" == "200" ]]; then
  echo "✅ /health endpoint reachable (HTTP 200)"
else
  echo "❌ /health endpoint returned HTTP $HEALTH_RESPONSE"
fi