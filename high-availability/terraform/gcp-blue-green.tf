provider "google" {
  project = "<YOUR_PROJECT_ID>"
  region  = "<YOUR_REGION>"
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
    port        = 80
    request_path = "/health"  # Adjust this to your health check endpoint
  }
}

resource "google_container_cluster" "blue_cluster" {
  name     = "blue-cluster"
  location = "<YOUR_ZONES>"
  # Add configuration for the blue cluster
}

resource "google_container_cluster" "green_cluster" {
  name     = "green-cluster"
  location = "<YOUR_ZONES>"
  # Add configuration for the green cluster
}

resource "google_compute_backend_service" "blue_backend" {
  name          = "blue-backend-service"
  port_name     = "http"
  protocol      = "HTTP"
  health_checks = [google_compute_health_check.http_health_check.id]

  backend {
    group = google_container_cluster.blue_cluster.instance_group # Reference to the blue cluster's instance group
  }
}

resource "google_compute_backend_service" "green_backend" {
  name          = "green-backend-service"
  port_name     = "http"
  protocol      = "HTTP"
  health_checks = [google_compute_health_check.http_health_check.id]

  backend {
    group = google_container_cluster.green_cluster.instance_group # Reference to the green cluster's instance group
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
