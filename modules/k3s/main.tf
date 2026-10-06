locals {
  kubeconfig_path = abspath(pathexpand(var.kubeconfig_path))
}

data "aws_region" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "master" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile
  key_name               = var.key_name

  user_data = templatefile("${path.module}/scripts/master_user_data.sh.tftpl", {
    parameter_name            = "/k3s/${var.name}-master/token"
    kubeconfig_parameter_name = "/k3s/${var.name}-master/kubeconfig"
  })

  tags = {
    Name = "${var.name}-master"
    Role = "k3s-master"
  }
}

resource "terraform_data" "master_ready" {
  triggers_replace = [aws_instance.master.id]

  provisioner "local-exec" {
    command     = "bash \"$WAIT_SCRIPT\""
    interpreter = ["bash", "-c"]

    environment = {
      WAIT_SCRIPT = abspath("${path.module}/scripts/wait-for-node.sh")
      AWS_REGION  = data.aws_region.current.region
      INSTANCE_ID = aws_instance.master.id
      NODE_NAME   = "k3s-master"
    }
  }
}

resource "aws_instance" "worker" {
  depends_on = [terraform_data.master_ready]

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile
  key_name               = var.key_name

  user_data = templatefile("${path.module}/scripts/worker_user_data.sh.tftpl", {
    master_private_ip = aws_instance.master.private_ip
    cluster_parameter = "/k3s/${var.name}-master/token"
  })

  tags = {
    Name = "${var.name}-worker"
    Role = "k3s-worker"
  }
}

# Query the master to verify that the worker actually joined Kubernetes.
resource "terraform_data" "worker_ready" {
  triggers_replace = [aws_instance.master.id, aws_instance.worker.id]

  provisioner "local-exec" {
    command     = "bash \"$WAIT_SCRIPT\""
    interpreter = ["bash", "-c"]

    environment = {
      WAIT_SCRIPT = abspath("${path.module}/scripts/wait-for-node.sh")
      AWS_REGION  = data.aws_region.current.region
      INSTANCE_ID = aws_instance.master.id
      NODE_NAME   = "k3s-worker"
    }
  }
}

# Expose the path only after the download provisioner completes. The Helm
# provider references this output so it depends on the kubeconfig resource.
resource "terraform_data" "kubeconfig" {
  depends_on = [terraform_data.worker_ready]

  input = local.kubeconfig_path

  triggers_replace = [
    aws_instance.master.id,
    aws_instance.master.public_ip,
    local.kubeconfig_path,
    filesha256("${path.module}/scripts/fetch-kubeconfig.sh"),
  ]

  provisioner "local-exec" {
    command     = "bash \"$FETCH_SCRIPT\""
    interpreter = ["bash", "-c"]

    environment = {
      FETCH_SCRIPT    = abspath("${path.module}/scripts/fetch-kubeconfig.sh")
      AWS_REGION      = data.aws_region.current.region
      PARAMETER_NAME  = "/k3s/${var.name}-master/kubeconfig"
      KUBECONFIG_PATH = local.kubeconfig_path
      EXPECTED_SERVER = "https://${aws_instance.master.public_ip}:6443"
    }
  }
}
