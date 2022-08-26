data "google_compute_default_service_account" "default" {
}

data "google_compute_image" "my_image" {
  family  = "debian-11"
  project = "debian-cloud"
}

resource "google_compute_instance_template" "foobar" {
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
    network = "default"

#  Uncomment if private google api access is not enabled on the VPC subnet
#    access_config {
#      // Ephemeral public IP
#    }
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
