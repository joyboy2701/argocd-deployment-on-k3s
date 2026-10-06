variable "name" {
  description = "Name prefix for the K3s master, worker, and SSM parameters."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC containing the cluster nodes."
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet in which both cluster nodes are provisioned."
  type        = string
}

variable "security_group_id" {
  description = "Security group attached to both cluster nodes."
  type        = string
}

variable "instance_profile" {
  description = "IAM instance profile granting access to SSM."
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair name for the cluster nodes."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type used for both cluster nodes."
  type        = string
}

variable "ssh_cidr" {
  description = "CIDR allowed to access the cluster by the root networking module."
  type        = string
}

variable "kubeconfig_path" {
  description = "Local kubeconfig destination downloaded from SSM after both nodes are ready."
  type        = string
  default     = "~/.kube/k3s-argocd-demo.yaml"
}
