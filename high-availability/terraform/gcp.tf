provider "google" {
  project    = "energy-stars"
  region     = "us-central1"
}

resource "google_compute_global_address" "default" {
  name = "global-ip-address"
}

resource "google_compute_health_check" "http_health_check" {
  name                = "http-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port = 80
    request_path = "/health"  # Adjust this to your health check endpoint
  }
}

resource "google_compute_backend_service" "blue_backend" {
  name          = "blue-backend-service"
  port_name     = "http"
  protocol      = "HTTP"
  health_checks = [google_compute_health_check.http_health_check.id]

  backend {
    group = google_container_cluster.my_gke_cluster.id  # Add your cluster's instance group
    # You may configure other options like capacity or balancing mode here
  }
}

resource "google_compute_backend_service" "green_backend" {
  name          = "green-backend-service"
  port_name     = "http"
  protocol      = "HTTP"
  health_checks = [google_compute_health_check.http_health_check.id]

  backend {
    group = google_container_cluster.my_gke_cluster.id  # Add your cluster's instance group
  }
}

resource "google_compute_url_map" "url_map" {
  name = "blue-green-url-map"

  default_service = google_compute_backend_service.blue_backend.id

  host_rule {
    hosts = ["example.com"]  # Adjust to your domain
    path_matcher = "blue-green-path-matcher"
  }

  path_matcher {
    name = "blue-green-path-matcher"

    default_service = google_compute_backend_service.blue_backend.id

    path_rule {
      paths = ["/*"]
      service = google_compute_backend_service.blue_backend.id
    }

    path_rule {
      paths = ["/green/*"]  # Route specific traffic to green version
      service = google_compute_backend_service.green_backend.id
    }
  }
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "http-target-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "forwarding_rule" {
  name        = "global-forwarding-rule"
  target      = google_compute_target_http_proxy.http_proxy.id
  port_range  = "80"
  ip_address  = google_compute_global_address.default.address
}


resource "google_container_cluster" "my_gke_cluster" {
  name               = "my-gke-cluster"
  location           = "<YOUR_REGION>" # e.g. us-central1
  initial_node_count = 1

  # Enable API access
  enable_kubernetes_alpha = false
  remove_default_node_pool = true

  # Add other options as desired (like network settings)
}

resource "google_container_node_pool" "frontend_node_pool" {
  provider = google

  cluster    = google_container_cluster.my_gke_cluster.name
  location   = google_container_cluster.my_gke_cluster.location
  name       = "frontend-pool"

  node_count = 1  # Initial node count

  autoscaling {
    min_nodes = 3
    max_nodes = 10
  }

  node_config {
    machine_type = "e2-standard-2"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    # Add additional configurations or customizations here
    # Example: 
    # disk_type    = "pd-standard"
    # disk_size_gb = 100
  }
}

resource "google_container_node_pool" "backend_node_pool" {
  provider = google

  cluster    = google_container_cluster.my_gke_cluster.name
  location   = google_container_cluster.my_gke_cluster.location
  name       = "backend-pool"

  node_count = 1  # Initial node count

  autoscaling {
    min_nodes = 3
    max_nodes = 10
  }

  node_config {
    machine_type = "e2-standard-4"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_container_node_pool" "database_node_pool" {
  provider = google

  cluster    = google_container_cluster.my_gke_cluster.name
  location   = google_container_cluster.my_gke_cluster.location
  name       = "database-pool"

  node_count = 1  # Initial node count

  autoscaling {
    min_nodes = 2
    max_nodes = 5
  }

  node_config {
    machine_type = "db-n1-standard-4"  # Use appropriate machine type for DB
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
