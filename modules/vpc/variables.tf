variable "name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidr" {
  type = string
}

variable "availability_zone" {
  type    = string
  default = null
}

variable "ssh_cidr" {
  type = string
}
