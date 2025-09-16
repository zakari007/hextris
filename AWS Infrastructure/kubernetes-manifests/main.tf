terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "domain_name" {
  default = "hextris.work.gd"
}

# VPC
resource "aws_vpc" "hextris_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "hextris-vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.hextris_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = {
    Name = "hextris-public-subnet"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.hextris_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name = "hextris-private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.hextris_vpc.id
  tags = {
    Name = "hextris-igw"
  }
}

# NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags = {
    Name = "hextris-nat-gw"
  }
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.hextris_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "hextris-public-rt"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.hextris_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = {
    Name = "hextris-private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# EKS Cluster
resource "aws_eks_cluster" "hextris_cluster" {
  name     = "hextris-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  # version  = ">= 1.24"

  vpc_config {
    subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.private_subnet.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# EKS Node Group (Master - Public)
resource "aws_eks_node_group" "master_nodes" {
  cluster_name    = aws_eks_cluster.hextris_cluster.name
  node_group_name = "master-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [aws_subnet.public_subnet.id]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
  ]
}

# EKS Node Group (Worker - Private)
resource "aws_eks_node_group" "worker_nodes" {
  cluster_name    = aws_eks_cluster.hextris_cluster.name
  node_group_name = "worker-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [aws_subnet.private_subnet.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.small"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
  ]
}

# IAM Roles and Policies
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

# SSL Certificate (using Let's Encrypt via Terraform)
resource "tls_private_key" "hextris_private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "hextris_cert" {
  private_key_pem = tls_private_key.hextris_private_key.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "Hextris"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

# Outputs
output "eks_cluster_name" {
  value = aws_eks_cluster.hextris_cluster.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.hextris_cluster.endpoint
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  value = aws_subnet.private_subnet.id
}

output "ssl_certificate" {
  value = tls_self_signed_cert.hextris_cert.cert_pem
}

output "ssl_private_key" {
  value = tls_private_key.hextris_private_key.private_key_pem
  sensitive = true
}