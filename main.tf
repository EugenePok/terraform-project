terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = "us-east-1"
  access_key = "access"
  secret_key = "secret"
}

# 1. Create vpc
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main_vpc.id
}

# 3. Create Custom Route Table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }
}

# 4. Create a Subnet
resource "aws_subnet" "main_vpc_public_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  depends_on        = [aws_internet_gateway.gw]
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "main_vpc_route_table_association" {
  subnet_id      = aws_subnet.main_vpc_public_subnet.id
  route_table_id = aws_route_table.route_table.id
}

# 6. Create Security Group to allow port 22,80,443
resource "aws_security_group" "http_https_ssh_sg" {
  name   = "http_https_ssh_sg"
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "network_interface" {
  subnet_id       = aws_subnet.main_vpc_public_subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.http_https_ssh_sg.id]
}


# 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
  domain     = "vpc"
  instance   = aws_instance.web.id
  depends_on = [aws_internet_gateway.gw, aws_instance.web]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}


# 9. Create Ubuntu server and install/enable apache2
resource "aws_instance" "web" {
  ami               = "ami-04b70fa74e45c3917"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "main-key"
  network_interface {
    network_interface_id = aws_network_interface.network_interface.id
    device_index         = 0
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                EOF
}
