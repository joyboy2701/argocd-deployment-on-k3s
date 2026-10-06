locals {
  application_yaml = <<-YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-nginx
  namespace: ${var.namespace}
spec:
  project: default
  source:
    repoURL: ${var.git_repo_url}
    targetRevision: ${var.git_revision}
    path: ${var.kustomize_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML
}

resource "aws_ssm_association" "application" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 600

  targets {
    key    = "InstanceIds"
    values = [var.master_instance_id]
  }

  parameters = {
    commands = join("\n", [
      "set -eu",
      "cat > /tmp/demo-nginx-application.yaml <<'EOF'\n${local.application_yaml}EOF",
      "sudo k3s kubectl apply -f /tmp/demo-nginx-application.yaml",
      "sudo k3s kubectl -n ${var.namespace} wait --for=condition=Available --timeout=600s deployment/argocd-server"
    ])
  }
}
