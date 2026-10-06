module "vpc" {
  source = "./modules/vpc"

  name               = coalesce(var.vpc.name, var.project.project_name)
  vpc_cidr           = var.vpc.vpc_cidr
  public_subnet_cidr = var.vpc.public_subnet_cidr
  availability_zone  = var.vpc.availability_zone
  ssh_cidr           = var.vpc.ssh_cidr
}

module "iam" {
  source = "./modules/iam"

  name = coalesce(var.iam.name, var.project.project_name)
}

module "k3s" {
  source = "./modules/k3s"

  name              = coalesce(var.k3s.name, var.project.project_name)
  vpc_id            = module.vpc.vpc_id
  public_subnet_id  = module.vpc.public_subnet_id
  security_group_id = module.vpc.k3s_security_group_id
  instance_profile  = module.iam.instance_profile_name
  key_name          = var.k3s.key_name
  instance_type     = var.k3s.instance_type
  ssh_cidr          = var.vpc.ssh_cidr

  depends_on = [module.iam, module.vpc]
}

module "helm" {
  source = "./modules/helm"

  releases = var.helm.releases

  depends_on = [module.k3s]
}

module "application" {
  source = "./modules/application"

  master_instance_id = module.k3s.master_instance_id
  namespace          = module.helm.releases["argocd"].namespace
  git_repo_url       = var.application.git_repo_url
  git_revision       = var.application.git_revision
  kustomize_path     = var.application.kustomize_path

  depends_on = [module.helm]
}
