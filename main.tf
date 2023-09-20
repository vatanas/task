// Configure the Google Cloud provider
provider "google" {
 credentials = file("gcpCreds.json")
 project     = var.project_id
}

//Configuring Kubernetes Provider
provider "kubernetes" {}

//Creating VPC Network
resource "google_compute_network" "vpc_network1" {
  name        = "prod-wp-env"
  description = "VPC Network for WordPress"
  project     = var.project_id
  auto_create_subnetworks = false
}

//Creating Subnetwork for VPC
resource "google_compute_subnetwork" "subnetwork1" {
  name          = "wp-subnet"
  ip_cidr_range = "10.2.0.0/16"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc_network1.id

  depends_on = [
    google_compute_network.vpc_network1
  ]
}

//Creating Firewall for VPC Network
resource "google_compute_firewall" "firewall1" {
  name    = "wp-firewall"
  network = google_compute_network.vpc_network1.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }

  source_tags = ["wp", "wordpress"]

  depends_on = [
    google_compute_network.vpc_network1
  ]
}


//Configuring SQL Database instance
resource "google_sql_database_instance" "sqldb_Instance" {
  name             = "sql1"
  database_version = "MYSQL_5_6"
  region           = var.region
  root_password    = var.root_pass

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true

      authorized_networks {
        name  = "sqlnet"
        value = "0.0.0.0/0"
      }
    }
  }

  depends_on = [
    google_compute_subnetwork.subnetwork1
  ]
}

//Creating SQL Database
resource "google_sql_database" "sql_db" {
  name     = var.database
  instance = google_sql_database_instance.sqldb_Instance.name

  depends_on = [
    google_sql_database_instance.sqldb_Instance
  ]  
}

//Creating SQL Database User
resource "google_sql_user" "dbUser" {
  name     = var.db_user
  instance = google_sql_database_instance.sqldb_Instance.name
  password = var.db_user_pass

  depends_on = [
    google_sql_database_instance.sqldb_Instance
  ]
}

//Creating Container Cluster
resource "google_container_cluster" "gke_cluster1" {
  name     = "my-cluster"
  description = "My GKE Cluster"
  project = var.project_id
  location = var.region
  network = google_compute_network.vpc_network1.name
  subnetwork = google_compute_subnetwork.subnetwork1.name
  remove_default_node_pool = true
  initial_node_count       = 1

  depends_on = [
    google_compute_subnetwork.subnetwork1
  ]
}

//Creating Node Pool For Container Cluster
resource "google_container_node_pool" "nodepool1" {
  name       = "my-node-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.gke_cluster1.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-micro"
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  depends_on = [
    google_container_cluster.gke_cluster1
  ]
}

//Set Current Project in gcloud SDK
resource "null_resource" "set_gcloud_project" {
  provisioner "local-exec" {
    command = "gcloud config set project ${var.project_id}"
  }  
}

//Configure Kubectl with Our GCP K8s Cluster
resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.gke_cluster1.name} --region ${google_container_cluster.gke_cluster1.location} --project ${google_container_cluster.gke_cluster1.project}"
  }  

  depends_on = [
    null_resource.set_gcloud_project,
    google_container_cluster.gke_cluster1
  ]
}

//WordPress Deployment
resource "kubernetes_deployment" "wp-dep" {
  metadata {
    name   = "wp-dep"
    labels = {
      env     = "Production"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        pod     = "wp"
        env     = "Production"
      }
    }

    template {
      metadata {
        labels = {
          pod     = "wp"
          env     = "Production"
        }
      }

      spec {
        container {
          image = "wordpress"
          name  = "wp-container"

          env {
            name  = "WORDPRESS_DB_HOST"
            value = "${google_sql_database_instance.sqldb_Instance.ip_address.0.ip_address}"
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = var.db_user
          }
          env {
            name  = "WORDPRESS_DB_PASSWORD"
            value = var.db_user_pass
          }
          env{
            name  = "WORDPRESS_DB_NAME"
            value = var.database
          }
          env{
            name  = "WORDPRESS_TABLE_PREFIX"
            value = "wp_"
          }

          port {
            container_port = 80
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.set_gcloud_project,
    google_container_cluster.gke_cluster1,
    google_container_node_pool.nodepool1,
    null_resource.configure_kubectl
  ]
}

//Creating LoadBalancer Service
resource "kubernetes_service" "wpService" {
  metadata {
    name   = "wp-svc"
    labels = {
      env     = "Production" 
    }
  }  

  spec {
    type     = "LoadBalancer"
    selector = {
      pod = "${kubernetes_deployment.wp-dep.spec.0.selector.0.match_labels.pod}"
    }

    port {
      name = "wp-port"
      port = 80
    }
  }

  depends_on = [
    kubernetes_deployment.wp-dep,
  ]
}

// Configuring IAP 
data "google_iam_policy" "admin" {
  binding {
    role = "roles/iap.httpsResourceAccessor"
    members = [
      "user:atanas.v@europe-cloud.com",
    ]
  }
}

resource "google_iap_web_iam_policy" "policy" {
  project = var.project_id
  policy_data = data.google_iam_policy.admin.policy_data
}

//Outputs
output "wp_service_url" {
  value = kubernetes_service.wpService.status[0].load_balancer_ingress[0].ip
  depends_on = [kubernetes_service.wpService]
}

//Open WordPress Site Automatically
resource "null_resource" "open_wp" {
  provisioner "local-exec" {
    command = "start chrome ${kubernetes_service.wpService.status[0].load_balancer_ingress[0].ip}" 
  }

  depends_on = [
    kubernetes_service.wpService
  ]
}
