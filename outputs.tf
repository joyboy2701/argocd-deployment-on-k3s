output "master_instance_id" {
  value = module.k3s.master_instance_id
}

output "worker_instance_id" {
  value = module.k3s.worker_instance_id
}

output "master_public_ip" {
  value = module.k3s.master_public_ip
}

output "argocd_url" {
  value = "http://${module.k3s.master_public_ip}:30080"
}

output "argocd_namespace" {
  value = module.helm.releases["argocd"].namespace
}

output "helm_releases" {
  description = "Configured Helm releases and their target namespaces."
  value       = module.helm.releases
}

output "kubeconfig_path" {
  description = "Absolute local kubeconfig path used by the Helm provider."
  value       = module.k3s.kubeconfig_path
}

output "kubeconfig_parameter" {
  description = "SSM SecureString parameter containing the master kubeconfig."
  value       = module.k3s.kubeconfig_parameter
}
