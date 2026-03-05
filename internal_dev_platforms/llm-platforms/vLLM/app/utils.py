import json
import ray

def print_ray_resources():
    """Print Ray cluster resources and GPU allocation per node."""
    try:
        cluster_resources = ray.cluster_resources()
        print("Ray Cluster Resources:")
        print(json.dumps(cluster_resources, indent=2))

        nodes = ray.nodes()
        print(f"\nDetected {len(nodes)} Ray node(s):")

        for node in nodes:
            node_id = node.get("NodeID", "N/A")[:8]  # Truncate for readability
            ip_address = node.get("NodeManagerAddress", "N/A")
            resources = node.get("Resources", {})
            num_gpus = int(resources.get("GPU", 0))

            print(f"  • Node {node_id}... | IP: {ip_address} | GPUs: {num_gpus}")

            # Show specific GPU IDs if available
            gpu_ids = [k for k in resources.keys() if k.startswith("GPU_ID_")]
            if gpu_ids:
                print(f"    GPU IDs: {', '.join(gpu_ids)}")

    except Exception as e:
        print(f"Error querying Ray cluster: {e}")

# Display current resources
# print_ray_resources()
