#!/bin/bash

# Kubernetes Image Inventory Script
# Collects all images from deployments, daemonsets, and statefulsets
# Output format suitable for Confluence table import

OUTPUT_FILE="${OUTPUT_FILE:-/tmp/k8s-images.txt}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Function to get images from a resource type
get_images() {
    local resource_type=$1
    kubectl get $resource_type --all-namespaces -o json | jq -r '
        .items[] | 
        .metadata.namespace as $ns |
        .metadata.name as $name |
        .spec.template.spec.containers[]? |
        [$ns, "'$resource_type'", $name, .name, .image] |
        @tsv
    ' 2>/dev/null
}

# Create header
cat > "$OUTPUT_FILE" << EOF
Kubernetes Image Inventory
Last Updated: $TIMESTAMP

|| Namespace || Resource Type || Resource Name || Container Name || Image ||
EOF

# Collect images from different resource types
{
    get_images "deployment"
    get_images "daemonset"
    get_images "statefulset"
} | sort | while IFS=$'\t' read -r namespace resource_type resource_name container_name image; do
    echo "| $namespace | $resource_type | $resource_name | $container_name | $image |" >> "$OUTPUT_FILE"
done

# Add summary
echo "" >> "$OUTPUT_FILE"
echo "---" >> "$OUTPUT_FILE"
echo "Total images found: $(grep -c "^|" "$OUTPUT_FILE" | awk '{print $1-1}')" >> "$OUTPUT_FILE"

echo "Image inventory written to: $OUTPUT_FILE"