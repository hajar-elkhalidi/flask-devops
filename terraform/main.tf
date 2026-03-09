terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

provider "oci" {
  config_file_profile = "DEFAULT"
}

variable "compartment_id" { default = "ocid1.compartment.oc1..aaaaaaaaaeuasrvep7uff76bwzj3ozznacvtmwmwe4rkdmve4p3625fitypa" }
variable "availability_domain" { default = "jHyU:AF-CASABLANCA-1-AD-1" }

# Image Ubuntu 22.04
data "oci_core_images" "ubuntu" {
  compartment_id = var.compartment_id
  operating_system = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape = "VM.Standard.E2.1.Micro"
}

# VCN (reseau virtuel)
resource "oci_core_vcn" "devops_vcn" {
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "devops-vcn"
}

# Subnet publique
resource "oci_core_subnet" "public_subnet" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.devops_vcn.id
  cidr_block     = "10.0.1.0/24"
  display_name   = "public-subnet"
}

# VM Master Node
resource "oci_core_instance" "master" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  shape               = "VM.Standard.E2.1.Micro"
  display_name        = "k8s-master"

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file("~/.ssh/id_rsa.pub")
  }
}

# VM Worker Node
resource "oci_core_instance" "worker" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  shape               = "VM.Standard.E2.1.Micro"
  display_name        = "k8s-worker"

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file("~/.ssh/id_rsa.pub")
  }
}

output "master_public_ip" { value = oci_core_instance.master.public_ip }
output "worker_public_ip" { value = oci_core_instance.worker.public_ip }
