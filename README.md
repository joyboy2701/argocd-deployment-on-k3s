# Modular Terraform K3s + Argo CD + Kustomize Assignment

This project provisions a small AWS lab environment with a modular Terraform structure:

```text
Terraform
├── VPC module
├── IAM module
├── K3s module
│   ├── master EC2 instance
│   └── worker EC2 instance
├── Helm module
│   └── Helm provider installation
└── Application module
    └── Argo CD Application + Kustomize

AWS
└── K3s master
    └── K3s worker
         └── Argo CD
              └── demo application from Git
                   └── Kustomize overlay
```

## Important design

A single Terraform apply creates the K3s infrastructure, waits for both nodes,
fetches the master kubeconfig to the configured local path, and installs Argo CD
and its Application. The Terraform runner must be able to reach the
master on TCP port 6443; its source address must be included in `vpc.ssh_cidr`.

Terraform creates:

1. VPC, subnet, route table and security group.
2. IAM role/profile for the EC2 instances.
3. K3s master.
4. K3s worker.
5. Argo CD using the Terraform Helm provider.
6. An Argo CD `Application` object pointing to the Kustomize overlay in Git.
7. Argo CD syncs the demo application.

The worker obtains the K3s token from AWS SSM Parameter Store. No manual token copy is required.

## Repository layout

```text
.
├── terraform/
│   ├── main.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── config/dev.tfvars
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vpc/
│       ├── iam/
│       ├── k3s/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── scripts/
│       │       ├── master_user_data.sh.tftpl
│       │       ├── worker_user_data.sh.tftpl
│       │       ├── wait-for-node.sh
│       │       └── fetch-kubeconfig.sh
│       ├── helm/
│       └── application/
└── kustomize/
    ├── base/
    └── overlays/
        └── dev/
```

## Prerequisites

- AWS account
- Terraform >= 1.6
- AWS CLI configured with the same account/credentials used by Terraform
- kubectl installed locally
- Local AWS credentials with ssm:GetParameter and KMS decryption access to the kubeconfig
- Local AWS credentials with ssm:SendCommand and ssm:GetCommandInvocation for node readiness checks
- An EC2 key pair
- A Git repository containing this project, or at least the `kustomize/` directory

## Configure

Edit `terraform/config/dev.tfvars`. Root inputs are grouped into typed objects:
`project`, `vpc`, `iam`, `k3s`, `helm`, and `application`. Set the EC2 key pair
in `k3s.key_name`, your allowed source CIDR in `vpc.ssh_cidr`, and the Git
repository in `application.git_repo_url`. The repository must be reachable by Argo CD.

All release definitions and chart overrides live in `helm.releases` in that
variable file. There are no default releases in Terraform locals. Keep an
`argocd` entry for the Application module; additional entries install additional
charts. The Application namespace comes from the `argocd` release. Module name
prefixes default to `project.project_name` and can be overridden in `vpc.name`,
`iam.name`, and `k3s.name`.

`terraform.tfvars.example` shows the same grouped structure for a new environment.
Load the chosen environment explicitly with `-var-file=config/dev.tfvars`.

The Helm provider uses the locally fetched kubeconfig at
`~/.kube/k3s-argocd-demo.yaml` by default. The K3s bootstrap adds the master's
public IP to the API certificate so this local kubeconfig can connect directly.

## Deploy

```bash
terraform init
terraform fmt -recursive
terraform validate

# Run from terraform/. Creates K3s, fetches its kubeconfig, and deploys Argo CD.
terraform apply -var-file=config/dev.tfvars
```

The K3s module directly contains `aws_instance.master`, `aws_instance.worker`,
and the local kubeconfig download resource. All bootstrap and download scripts
are in `modules/k3s/scripts/`. A moved block in the root `main.tf` migrates the
previous root kubeconfig resource into the module. Review a plan before applying
to an existing deployment.

The variable file is `config/dev.tfvars` relative to the `terraform/` directory.
No local SSH private key is needed.

The master publishes its kubeconfig as an SSM SecureString at
`/k3s/<project_name>-master/kubeconfig`. A Terraform `local-exec` downloads it
with decryption, checks that it points to the current master, waits for the
authenticated Kubernetes API readiness endpoint, and saves it with mode 600.
The value is fetched by AWS CLI, so kubeconfig credentials are not stored in
Terraform state. Intelligent-Tiering allows AWS to use an advanced parameter
if the kubeconfig exceeds the standard size limit (advanced parameter charges
may apply).

The deployment enforces this sequence:

1. Create networking and IAM.
2. Create the master; use SSM to wait for its bootstrap to publish credentials
   and for its Kubernetes node to become Ready.
3. Create the worker; use SSM on the master to wait for the worker node to join
   and become Ready.
4. Fetch the kubeconfig locally, select its context, and verify API readiness.
5. Install Argo CD through Helm.
6. Apply the Argo CD Application through SSM; Argo CD syncs the Git manifests.

A readiness failure stops deployment before the next stage. These checks use
SSM rather than a local SSH private key.

The K3s module owns the kubeconfig download resource and its script.
The Helm provider uses `module.k3s.kubeconfig_path` for `config_path`,
with the configured local path as a fallback for older states whose download
resource has a null output.
On a fresh apply, that output is unknown until the local download completes,
which connects provider initialization to the download resource. A dependency
on the download also ensures the Helm release is applied afterward. No
targeted apply or second apply is required.

The download reruns when the master, its public IP, the configured path, or the
download script changes. Keep the local kubeconfig for later plans and destroy
operations, since Helm refreshes existing releases during planning. If moving
an existing deployment to a new machine, restore its kubeconfig from SSM before
planning existing Helm resources.

The default path is `~/.kube/k3s-argocd-demo.yaml`; override it with
`helm.kubeconfig_path`. The Helm provider explicitly uses that path, so deployment
does not depend on a shell `KUBECONFIG` export. After apply completes, use the
output in a later terminal:

```bash
export KUBECONFIG="$(terraform output -raw kubeconfig_path)"
kubectl get nodes
```

Your current public IP must be allowed by `vpc.ssh_cidr` to reach TCP 6443.
A kubeconfig alone cannot fix blocked network access.

## Get the Argo CD endpoint

```bash
terraform output argocd_url
```

The lab exposes Argo CD through a NodePort on the master.

Get the initial admin password:

```bash
aws ssm send-command \
  --instance-ids "$(terraform output -raw master_instance_id)" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo /usr/local/bin/kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d; echo"]' \
  --query 'Command.CommandId' \
  --output text
```

For a simple lab, the generated Argo CD URL is HTTP. Do not use this exposure pattern for production.

## Verify

On the master:

```bash
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
sudo k3s kubectl get applications -n argocd
```

The expected nodes are:

```text
k3s-master   Ready
k3s-worker   Ready
```

The expected application is:

```text
demo-nginx
```

## Kustomize

Base:

```text
kustomize/base/
├── deployment.yaml
├── service.yaml
└── kustomization.yaml
```

Dev overlay:

```text
kustomize/overlays/dev/
└── kustomization.yaml
```

The overlay changes the replica count and image tag. Argo CD watches:

```text
kustomize/overlays/dev
```

Change the image tag or replicas, push to Git, and Argo CD detects and syncs the change.

## Destroy

Set `helm.use_existing_kubeconfig = true` in `config/dev.tfvars` to use the
local kubeconfig directly during destroy.

```bash
terraform destroy -var-file=config/dev.tfvars
```

## Assignment objectives

This demonstrates:

- Terraform modularization
- Custom VPC module
- IAM module
- One K3s module containing both master and worker resources
- K3s master/worker bootstrap
- AWS SSM instead of manually distributing SSH credentials
- Helm-based Argo CD installation
- GitOps
- Argo CD Application
- Kustomize base/overlay
- Automated application deployment
