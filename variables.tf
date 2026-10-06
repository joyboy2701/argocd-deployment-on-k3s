variable "project" {
  description = "AWS region and shared project tags and resource name prefix."
  type = object({
    aws_region   = optional(string, "eu-west-1")
    project_name = optional(string, "k3s-argocd-demo")
    environment  = optional(string, "dev")
  })
  default = {}
}

variable "vpc" {
  description = "Network configuration and CIDR allowed to access SSH and the Kubernetes API."
  type = object({
    name               = optional(string)
    vpc_cidr           = optional(string, "10.50.0.0/16")
    public_subnet_cidr = optional(string, "10.50.1.0/24")
    availability_zone  = optional(string)
    ssh_cidr           = string
  })
}

variable "iam" {
  description = "IAM resource name prefix; defaults to the project name."
  type = object({
    name = optional(string)
  })
  default = {}
}

variable "k3s" {
  description = "K3s node configuration using an existing EC2 key pair."
  type = object({
    name          = optional(string)
    key_name      = string
    instance_type = optional(string, "t3.medium")
  })
}

variable "application" {
  description = "Git source for the Argo CD Application deployed to the argocd Helm release namespace."
  type = object({
    git_repo_url   = string
    git_revision   = optional(string, "main")
    kustomize_path = optional(string, "kustomize/overlays/dev")
  })
}

variable "helm" {
  description = "Helm connection settings and complete release map, including the required argocd release."
  type = object({
    kubeconfig_path         = optional(string, "~/.kube/k3s-argocd-demo.yaml")
    use_existing_kubeconfig = optional(bool, false)
    releases = map(object({
      name             = optional(string)
      repository       = optional(string)
      chart            = string
      version          = optional(string)
      namespace        = optional(string, "default")
      create_namespace = optional(bool, true)
      values           = optional(list(string), [])
      set              = optional(map(string), {})
      wait             = optional(bool, true)
      wait_for_jobs    = optional(bool, false)
      timeout          = optional(number, 600)
      atomic           = optional(bool, false)
      cleanup_on_fail  = optional(bool, false)
      skip_crds        = optional(bool, false)
    }))
  })

  validation {
    condition     = contains(keys(var.helm.releases), "argocd")
    error_message = "helm.releases must include argocd because the Application and root outputs depend on it."
  }
}
