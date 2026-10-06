output "master_instance_id" {
  description = "EC2 instance ID of the K3s master."
  value       = aws_instance.master.id
}

output "master_public_ip" {
  description = "Public IP of the K3s master API endpoint."
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Private IP used by the worker to join the master."
  value       = aws_instance.master.private_ip
}

output "worker_instance_id" {
  description = "EC2 instance ID of the K3s worker."
  value       = aws_instance.worker.id
}

output "kubeconfig_parameter" {
  description = "SSM Parameter Store name containing the encrypted master kubeconfig."
  value       = "/k3s/${var.name}-master/kubeconfig"
}

output "kubeconfig_path" {
  description = "Absolute local kubeconfig path, available after the download provisioner completes."
  value       = terraform_data.kubeconfig.output
}
