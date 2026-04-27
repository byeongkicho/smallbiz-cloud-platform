variable "project_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_instance_types" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}
