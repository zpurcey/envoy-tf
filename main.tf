# Create the healthcheck
resource "google_compute_health_check" "tcp_port_443_healthcheck" {
  name    = "tcp-443-health-check"

  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "443"
    port_specification = "USE_FIXED_PORT"
  }
}

data "google_compute_default_service_account" "default" {
}

data "google_compute_image" "my_image" {
  family  = "debian-11"
  project = "debian-cloud"
}

# Create the Forwarding rule
resource "google_compute_global_forwarding_rule" "adminweb_tcp_443_forwarding_rule" {
  provider = google-beta
  name = "adminweb-tcp-443-forwarding-rule"
  depends_on            = [google_compute_target_tcp_proxy.adminweb_tcp_443_td_proxy_unit]
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_SELF_MANAGED"
  port_range            = 443
  target = google_compute_target_tcp_proxy.adminweb_tcp_443_td_proxy_unit.id
  network      = "projects/apurcell-tf-cloud/global/networks/vpc-art-host"
  ip_address   = "0.0.0.0"
}

# Create instance template for TD envoy proxy
resource "google_compute_instance_template" "instance_template" {
  name           = "appserver-template"
  machine_type   = "e2-medium"
  can_ip_forward = false
  tags           = ["foo", "bar"]

  disk {
    source_image = data.google_compute_image.my_image.self_link
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = "projects/apurcell-tf-cloud/global/networks/vpc-art-host"
    subnetwork = "projects/apurcell-tf-cloud/regions/australia-southeast1/subnetworks/subnet-10-44-110-0-24-firewall" 
  }

  scheduling {
    preemptible       = false
    automatic_restart = true
  }

  metadata = {
    gce-software-declaration = <<-EOF
{ "softwareRecipes" : [{ "name" : "install-gce-service-proxy-agent", "desired_state" : "INSTALLED", "installSteps" : [{ "scriptRun" : { "script" : "#! /bin/bash\nZONE=$( curl --silent http://metadata.google.internal/computeMetadata/v1/instance/zone -H Metadata-Flavor:Google | cut -d/ -f4 )\nexport SERVICE_PROXY_AGENT_DIRECTORY=$(mktemp -d)\nsudo gsutil cp   gs://gce-service-proxy-$${ZONE}/service-proxy-agent/releases/service-proxy-agent-0.2.tgz   $${SERVICE_PROXY_AGENT_DIRECTORY}   || sudo gsutil cp     gs://gce-service-proxy/service-proxy-agent/releases/service-proxy-agent-0.2.tgz     $${SERVICE_PROXY_AGENT_DIRECTORY}\nsudo tar -xzf $${SERVICE_PROXY_AGENT_DIRECTORY}/service-proxy-agent-0.2.tgz -C $${SERVICE_PROXY_AGENT_DIRECTORY}\n$${SERVICE_PROXY_AGENT_DIRECTORY}/service-proxy-agent/service-proxy-agent-bootstrap.sh" } }] }] }
EOF
    gce-service-proxy        = <<-EOF
{ "_disclaimer" : "DISCLAIMER:\nThis service-proxy configuration format is not a public API and may change\nwithout notice. Please use gcloud command-line tool to run service proxy on\nGoogle Compute Engine.", "api-version" : "0.2", "proxy-spec" : { "network" : "" } }
EOF
    enable-guest-attributes  = "TRUE"
    enable-osconfig          = "true"

  }

  service_account {
    email  = data.google_compute_default_service_account.default.email
    scopes = ["cloud-platform"]
  }

  labels = {
    gce-service-proxy = "on"
  }
}

# Create the Instance Group
resource "google_compute_instance_group_manager" "Adminweb-tcp_443_traffic_director_instance_group-unit" {
  name               = "adminweb-tcp443-td-middleproxy-instancegroup-unit"
  base_instance_name = "adminweb-tcp443-td-middleproxy-instancegroup-unit"
  target_size        = 1
  version {
    instance_template = google_compute_instance_template.instance_template.id
  }
  named_port {
    name = "tcp443"
    port = 443
  }
  #Ensure the Template has been created before creating the Instance Group and Instances.
  depends_on = [google_compute_instance_template.instance_template]
}
