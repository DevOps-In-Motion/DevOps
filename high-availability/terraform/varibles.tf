variable "project_settings" {
  description = "Settings for GCP project."
  type = object({
    project_id         = string
    region             = string
    zone               = string
    machine_type       = string
    google_credentials = string
  })

  default = {
    project_id         = "ACME"
    region             = "value"
    zone               = "value"
    machine_type       = "n1-standard-1"  # Default value for machine type
    google_credentials  = "value"
  }

  validation {
    condition = length(var.project_settings.project_id) > 10
    error_message = "project_id must be more than 10 characters."
  }

  validation {
    condition = length(var.project_settings.region) > 5
    error_message = "region must be more than 5 characters."
  }

  validation {
    condition = length(var.project_settings.zone) > 5
    error_message = "zone must be more than 5 characters."
  }
}
