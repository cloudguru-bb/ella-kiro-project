# Terraform Specification: AWS Free Tier Infrastructure for ella-core
# Directory: /infra/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for deployment (AWS Free Tier eligible)."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment name."
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ella-core-cellular"
      ManagedBy   = "Terraform"
      Environment = var.environment
      FreeTier    = "true"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Networking Infrastructure (VPC, Subnet, Route Table)
# ------------------------------------------------------------------------------

resource "aws_vpc" "ella_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ella-vpc"
  }
}

resource "aws_internet_gateway" "ella_igw" {
  vpc_id = aws_vpc.ella_vpc.id

  tags = {
    Name = "ella-igw"
  }
}

resource "aws_subnet" "ella_public_subnet" {
  vpc_id                  = aws_vpc.ella_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "ella-public-subnet"
  }
}

resource "aws_route_table" "ella_public_rt" {
  vpc_id = aws_vpc.ella_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ella_igw.id
  }

  tags = {
    Name = "ella-public-rt"
  }
}

resource "aws_route_table_association" "ella_public_assoc" {
  subnet_id      = aws_subnet.ella_public_subnet.id
  route_table_id = aws_route_table.ella_public_rt.id
}

# ------------------------------------------------------------------------------
# 2. Security Group (SCTP, GTP-U, Management API)
# ------------------------------------------------------------------------------

resource "aws_security_group" "ella_sg" {
  name        = "ella-core-security-group"
  description = "Security rules for ella-core 5G/4G cellular signaling and management"
  vpc_id      = aws_vpc.ella_vpc.id

  # SSH Administration
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP in production
  }

  # N2 / S1-MME Control Plane (SCTP & UDP fallback for simulated gNodeB)
  ingress {
    description = "N2/S1-AP gNodeB Signaling (SCTP/UDP)"
    from_port   = 38412
    to_port     = 38412
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # N3 / S1-U User Plane Data Tunneling (GTP-U)
  ingress {
    description = "N3 GTP-U Data Tunneling"
    from_port   = 2152
    to_port     = 2152
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Management API & HTTP Healthcheck
  ingress {
    description = "ella-core REST API & Health Check"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Standard Outbound Access (Internet Egress for UEs via NAT)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ella-core-sg"
  }
}

# ------------------------------------------------------------------------------
# 3. IAM Role for CloudWatch Log Forwarding (Scoped Privilege)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "ella_instance_role" {
  name = "ella-instance-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy_attach" {
  role       = aws_iam_role.ella_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ella_instance_profile" {
  name = "ella-instance-profile"
  role = aws_iam_role.ella_instance_role.name
}

# ------------------------------------------------------------------------------
# 4. Ubuntu 24.04 LTS AMI Lookup & EC2 Instance
# ------------------------------------------------------------------------------

data "aws_ami" "ubuntu_noble" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "ella_host" {
  ami                  = data.aws_ami.ubuntu_noble.id
  instance_type        = "t3.micro" # AWS Free Tier eligible (750 hours/month)
  subnet_id            = aws_subnet.ella_public_subnet.id
  vpc_security_group_ids = [aws_security_group.ella_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ella_instance_profile.name

  # AWS Free Tier Storage Limits (Max 30GB total across free tier)
  root_block_device {
    volume_size           = 20 # 20 GB gp3 SSD
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = file("${path.module}/cloud-init.yaml")

  tags = {
    Name = "ella-core-host"
  }
}

# ------------------------------------------------------------------------------
# 5. Infrastructure Outputs
# ------------------------------------------------------------------------------

output "instance_public_ip" {
  value       = aws_instance.ella_host.public_ip
  description = "Public IP address of the ella-core EC2 host"
}

output "instance_id" {
  value       = aws_instance.ella_host.id
  description = "EC2 Instance ID for AWS CLI / Agent operations"
}

output "healthcheck_url" {
  value       = "http://${aws_instance.ella_host.public_ip}:8080/healthz"
  description = "HTTP Endpoint for Day-2 health checks"
}
