# =========================
# Локальні теги для всіх ресурсів
# =========================
locals {
  common_tags = {
    Owner   = var.prefix
    Project = "Terraform-IaC-Lab3"
    Managed = "Terraform"
  }
}

# =========================
# VPC
# =========================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, { Name = "${var.prefix}-vpc" })
}

# =========================
# Підмережі
# =========================
resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_a_cidr
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "${var.prefix}-subnet-a" })
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_b_cidr
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "${var.prefix}-subnet-b" })
}

# =========================
# Інтернет-шлюз та маршрут
# =========================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.prefix}-igw" })
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, { Name = "${var.prefix}-public-rt" })
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# =========================
# Security Group
# =========================
data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

resource "aws_security_group" "web_sg" {
  name        = "${var.prefix}-sg"
  description = "Managed by Terraform: Allow SSH from strict IP and HTTP from any"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH Access (Restricted)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  ingress {
    description = "Custom Web Port Access"
    from_port   = var.web_port
    to_port     = var.web_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.prefix}-sg" })
}

# =========================
# Key Pair для SSH
# =========================
resource "aws_key_pair" "my_key" {
  key_name   = "${var.prefix}-key"
  public_key = file(var.public_key_path) # наприклад, "~/.ssh/my_key.pub"
}

# =========================
# Ubuntu AMI
# =========================
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] 
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# =========================
# EC2 Інстанс
# =========================
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.ubuntu_2404.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.subnet_a.id

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  key_name = aws_key_pair.my_key.key_name

  user_data = templatefile("${path.module}/bootstrap.sh", {
    WEB_PORT      = var.web_port
    SERVER_NAME   = var.apache_server_name
    DOC_ROOT      = var.apache_doc_root
    STUDENT       = var.prefix
    APACHE_LOG_DIR = "/var/log/apache2"
  })

  tags = merge(local.common_tags, { Name = "${var.prefix}-ec2-web" })
}