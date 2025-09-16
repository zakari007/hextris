Hextris: DevOps Guide 
======================

<img src="images/twitter-opengraph.png" width="100px"><br>

This guide will help you containerize, deploy, and manage the Hextris game on AWS EKS Kubernetes cluster with full CI/CD pipeline.

## Prerequisites

Before you begin, ensure you have:

    GitHub Account with access to the repository

    Docker Hub Account for container registry

    AWS Account with appropriate permissions

    Domain Name (hextris.work.gd) configured with DNS ==> #https://freedomain.one/

    Basic knowledge of Docker, Kubernetes, and AWS
 
 ## Quick Start
1. Fork and Clone the Repository
```
git clone https://github.com/your-username/hextris.git
cd hextris
```

## Dockerfile
```
FROM node:18-alpine
WORKDIR /app
Copy package files first for better caching
COPY package*.json ./
RUN npm install
Copy application files
Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S hextris -u 1001 && \
    chown -R hextris:nodejs /app
USER hextris
EXPOSE 8080
CMD ["npm", "start"]
```

## Create AWS infrastructure with Terraform
<img width="961" height="515" alt="Image" src="https://github.com/user-attachments/assets/0f6cd70c-3cbc-4a17-b0c7-b42e2af5b2f3" />

Create VPC using Terraform Modules
```
# Create VPC Terraform Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.78.0"

  # VPC Basic Details
  name = "vpc-dev"
  cidr = "10.0.0.0/16"   
  azs                 = ["us-east-1a", "us-east-1b"]
  private_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets      = ["10.0.101.0/24", "10.0.102.0/24"]
```
 
Define Input Variables for VPC module and reference them in VPC Terraform Module
```
variable "aws_region" {
  description = "Region in which AWS Resources to be created"
  type = string
  default = "us-east-1"  
}
```
Define local values and reference them in VPC Terraform Module
```
# Define Local Values in Terraform
locals {
  owners = var.business_divsion
  environment = var.environment
  name = "${var.business_divsion}-${var.environment}"
  common_tags = {
    owners = local.owners
    environment = local.environment     
  }
}
```
Create terraform.tfvars to load variable values by default from this file
```
# Generic Variables
aws_region = "us-east-1"  
environment = "dev"
business_divsion = "Prod"
```
Create vpc.auto.tfvars to load variable values by default from this file related to a VPC
```
# VPC Variables
vpc_name = "myvpc"
vpc_cidr_block = "10.0.0.0/16"
vpc_availability_zones = ["us-east-1a", "us-east-1b"]
vpc_public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
vpc_private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
vpc_database_subnets= ["10.0.151.0/24", "10.0.152.0/24"]
```
Define Output Values for VPC
```
# VPC ID
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

# VPC CIDR blocks
output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

# VPC Private Subnets
output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

# VPC Public Subnets
output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}
```
Create AWS Security Group Terraform Module and define HTTP port 80, 22 inbound rule for entire internet access 0.0.0.0/0
```
module "public_bastion_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.18.0"

  name        = "public-bastion-sg"
  description = "Security group with SSH port open for everybody (IPv4 CIDR), egress ports are all world open"
  vpc_id      = module.vpc.vpc_id
  # Ingress Rules & CIDR Block  
  ingress_rules = ["ssh-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  # Egress Rule - all-all open
  egress_rules = ["all-all"]
  tags = local.common_tags  
}
```
Create Multiple EC2 Instances in VPC Private Subnets and install
```
module "private_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.18.0"

  name        = "private-sg"
  description = "Security group with HTTP & SSH ports open for everybody (IPv4 CIDR), egress ports are all world open"
  vpc_id      = module.vpc.vpc_id
  ingress_rules = ["ssh-tcp", "http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = ["all-all"]
  tags = local.common_tags  
}
```
Create EC2 Instance in VPC Public Subnet Bastion Host
```
module "ec2_public" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "2.17.0"
  # insert the 10 required variables here
  name = "${var.environment}-BastionHost"
  ami = data.aws_ami.amzlinux2.id 
  instance_type = var.instance_type
  key_name = var.instance_keypair
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids = [module.public_bastion_sg.this_security_group_id]    
  tags = local.common_tags
}
```
Create Elastic IP for Bastion Host EC2 Instance
```
resource "aws_eip" "bastion_eip" {
  depends_on = [module.ec2_public]
  instance =  module.ec2_public.id[0] 
  vpc = true
  tags = local.common_tags  
}
```
Create null_resource with following 3 Terraform Provisioners
        File Provisioner
        Remote-exec Provisioner
        Local-exec Provisioner
```
# Create a Null Resource and Provisioners
resource "null_resource" "name" {
  depends_on = [module.ec2_public ]
  # Connection Block for Provisioners to connect to EC2 Instance
  connection {
    type = "ssh"
    host = aws_eip.bastion_eip.public_ip
    user = "ec2-user"
    password = ""
    private_key = file("private-key/terraform-key.pem")
  } 

 # Copies the terraform-key.pem file to /tmp/terraform-key.pem
  provisioner "file" {
    source      = "private-key/terraform-key.pem"
    destination = "/tmp/terraform-key.pem"
  }  

# Using remote-exec provisioner fix the private key permissions on Bastion Host
  provisioner "remote-exec" {
    inline = [
      "sudo chmod 400 /tmp/terraform-key.pem"
    ]
  }  
  # local-exec provisioner (Creation-Time Provisioner - Triggered during Create Resource)
  provisioner "local-exec" {
    command = "echo VPC created on `date` and VPC ID: ${module.vpc.vpc_id} >> creation-time-vpc-id.txt"
    working_dir = "local-exec-output-files/"
    #on_failure = continue
  }
## Local Exec Provisioner:  local-exec provisioner (Destroy-Time Provisioner - Triggered during deletion of Resource)
  provisioner "local-exec" {
    command = "echo Destroy time prov `date` >> destroy-time-prov.txt"
    working_dir = "local-exec-output-files/"
    when = destroy
    #on_failure = continue
  }    
}
```

Execute Terraform Commands
```
# Terraform Initialize
terraform init

# Terraform Validate
terraform validate

# Terraform Plan
terraform plan

# Terraform Apply
terraform apply -auto-approve
```

Connect to Bastion EC2 Instance and Test
```
# Connect to Bastion EC2 Instance from local desktop
ssh -i private-key/terraform-key.pem ec2-user@<PUBLIC_IP_FOR_BASTION_HOST>

# Curl Test for Bastion EC2 Instance to Private EC2 Instances
curl  http://<Private-Instance-1-Private-IP>
curl  http://<Private-Instance-2-Private-IP>

# Connect to Private EC2 Instances from Bastion EC2 Instance
ssh -i /tmp/terraform-key.pem ec2-user@<Private-Instance-1-Private-IP>
```
Clean-Up
```
# Terraform Destroy
terraform destroy -auto-approve

# Clean-Up
rm -rf .terraform*
rm -rf terraform.tfstate*
```

## CI/CD pipeline
<img width="693" height="831" alt="Image" src="https://github.com/user-attachments/assets/f07bbe43-4bf5-4420-aebd-eb9ca194af80" />

CI CD with Github Actions

This section explains the Build and Publish Docker Image GitHub Actions. The workflow builds, tests, and publishes a Docker image for the Hextris project, and deploys it to an EC2 host.
Workflow file location: .github/workflows/test-build-docker_publish.yml

## Overview

This workflow runs on the following events:

`push`  to branches: main (or other branches if you update the triggers)

`pull_request` targeting main 

`release` when a release is published

workflow_dispatch for manual runs

The workflow defines two jobs:

1. `docker-build-test` — runs only for pull requests. Builds the image locally for the PR and runs lightweight runtime tests to ensure the container starts.

2. `docker-build-push`  — runs for pushes, releases. Builds the image, tags it, pushes to Docker Hub, runs runtime tests against the just-built image, updates the Docker Hub description on release, and deploys to an EC2 host via SSH.

## Environment variables

At the top of the workflow the following env variables are set for convenience:

`REGISTRY`: `docker.io`— the Docker registry host (Docker Hub by default).

`IMAGE_NAME`: `zakari007/hextris` — the image name used for tagging/pushing.

## Job: docker-build-test

Checkout repository — actions/checkout@v4 clones the repository so the build context is available.

Set up Docker Buildx — docker/setup-buildx-action@v3 configures Docker Buildx (multi-arch/build enhancements) inside the runner.

Build Docker image — docker/build-push-action@v5 builds the image using the repository root as the context and uses load: true to load the built image into the runner's local Docker daemon. The image is tagged as hextris:pr-${{ github.event.number }} so each PR has a distinct tag.

Test Docker image — runs a shell script which:

Starts the container detached: docker run -d --name hextris-test hextris:pr-${{ github.event.number }}

Waits a short time for the process to start

Checks docker ps for the container (ensures it is running)

If not running, prints container logs and fails the job

Stops and removes the test container to keep the environment clean


## Job: docker-build-push (build, push, test, deploy)

Run condition: if: github.event_name != 'pull_request' — runs for pushes, releases, and manual triggers.

Permissions:

contents: read — allows the workflow to read repository contents.

packages: write — permits publishing package artifacts if needed.

Checkout repository — clones the repo so build context is available.

Set up Docker Buildx — configures Buildx for building and pushing images.

Log in to Docker Hub — docker/login-action@v3 logs into Docker Hub using DOCKER_USERNAME and DOCKER_PASSWORD secrets.

Extract metadata for Docker — docker/metadata-action@v5 (id: meta) is used to generate image names, tags, and labels automatically. The images: input uses ${{ secrets.DOCKER_USERNAME }}/hextris and tags: are configured to produce several tag

Build and push Docker image — docker/build-push-action@v5 builds the image and (conditionally) pushes it to Docker Hub. Inputs:

context: . — build context

push: ${{ github.event_name != 'pull_request' }} — pushes only when not a pull request

tags: ${{ steps.meta.outputs.tags }} — tags coming from the metadata action

labels: ${{ steps.meta.outputs.labels }} — labels added from metadata

cache-from / cache-to: use GitHub Actions cache to speed up subsequent builds

## Test the built image

    Runs the image detached and maps 8080:8080
    
    Waits for the container to initialize
    
    Checks HTTP status (expects 200)
    
    Scrapes <title> from the web page and verifies it contains Hextris or Hex
    
    Prints logs and fails the job if checks fail
    
    Cleans up the test container













```
git clone https://github.com/your-username/hextris.git
cd hextris
```

Hextris was created by a group of high school friends in 2014.

## Press kit
http://hextris.github.io/presskit/info.html

## License
Copyright (C) 2018 Logan Engstrom

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
