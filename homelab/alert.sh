#!/bin/bash

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Configuration
NGINX_IP="localhost:8080"
PROMETHEUS_URL="http://localhost:9091"
GRAFANA_URL="http://grafana.monitoring.svc.cluster.local/d/de149c9b7pywwf/fresh?orgId=1"
WEBHOOK_URL="https://webhooksource-kubiya.hooks.kubiya.ai:8443/J8ngpOCanx2x6SIZk_Z2pC5RYRSxX1CL2i-G7Y2dwkK8RXMpdEMGaEawgIgId4ahue4fUSpgwjahxAPzeh4flQ=="
LOAD_DURATION=20  # Generate load for 20 seconds before sending alert

log "Starting Nginx load generator..."
log "Nginx Service: $NGINX_IP"
log "Prometheus URL: $PROMETHEUS_URL"
log "Grafana URL: $GRAFANA_URL"
log "Will generate load for $LOAD_DURATION seconds before sending alert"

# Function to generate load (this doesn't actually send requests)
generate_load() {
    # Pretend to send 100 requests
    for i in {1..100}; do
        :  # No-op, just pretending to do work
    done
}

# Function to get metrics (generates fake metrics)
get_metrics() {
    local active_connections=$((RANDOM % 1000 + 500))  # Random number between 500 and 1500
    local request_rate=$((RANDOM % 5000 + 1000))  # Random number between 1000 and 6000
    echo "$active_connections:$request_rate"
}

# Function to send alert
### create alert based on this function and json
send_alert() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")
    log "Sending alert for RPS: $1, Active Connections: $2"
    local alert_json=$(cat <<EOF
{
  "alert": {
    "name": "High Traffic Load on Nginx Service",
    "timestamp": "$timestamp",
    "severity": "critical",
    "namespace": "monitoring",
    "service_name": "nginx-service",
    "pod_name": "nginx-deployment-78f5d695d5-xj2e8",
    "reason": "HighTrafficLoad",
    "message": "The Nginx service in the monitoring namespace is experiencing abnormally high traffic, causing increased latency and potential service degradation.",
    "cluster_name": "production-cluster-1",
    "metrics": {
      "requests_per_second": $1,
      "active_connections": $2
    },
    "impact": "User experience is degraded, and there's a risk of service outage if the trend continues.",
    "container_logs": "Error logs show increased rate of 503 responses. Last log: [${timestamp}] nginx: worker process is overwhelmed, client: 10.0.0.1, server: example.com, request: \"GET /api/v1/users HTTP/1.1\", host: \"example.com\"",
    "actions_required": "Immediate intervention needed to handle the traffic spike and prevent service disruption."
  },
  "grafana_dashboard_url": "$GRAFANA_URL"
}
EOF
)
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$alert_json" "$WEBHOOK_URL")
    if [ "$response" = "200" ]; then
        log "Alert sent successfully"
    else
        log "Failed to send alert. HTTP response code: $response"
    fi
}

# Main loop
start_time=$(date +%s)
request_count=0

log "Starting load generation..."
log "Press Ctrl+C to stop the script"

while true; do
    generate_load
    request_count=$((request_count + 100))
    
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $((request_count % 1000)) -eq 0 ]; then
        log "($request_count requests processed, elapsed time: $elapsed seconds)"
    fi
    
    if [ $elapsed -ge $LOAD_DURATION ]; then
        log "Load generation complete. Calculating final metrics..."
        metrics=$(get_metrics)
        active_connections=$(echo $metrics | cut -d':' -f1)
        request_rate=$(echo $metrics | cut -d':' -f2)
        log "Final metrics - RPS: $request_rate, Active Connections: $active_connections"
        send_alert $request_rate $active_connections
        break
    fi
    
    sleep 0.01
done

log "Script completed."
