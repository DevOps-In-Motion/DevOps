locals {
  ssh_user = "ubuntu"
  key_name = "devops"
  private_key_path = "~/githubRepos/.ssh/devops.pem"
}

provider "aws" {
  region = "us-east-1" # Modify to your desired region
  access_key = var.AWS_ACCESS_KEY_ID 
  secret_key = var.AWS_SECRET_ACCESS_KEY
}


data "aws_vpc" "default" {
  default = true
}


data "aws_subnet" "subnet_1" {
  vpc_id = data.aws_vpc.default.id
  cidr_block = "172.31.64.0/20"
}

# Create a security group allowing SSH access from anywhere
resource "aws_security_group" "buildkite_sg" {
  name        = "buildkite_sg"
  description = "Security group for Buildkite agent"
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance for the Buildkite agent
resource "aws_instance" "buildkite_instance" {
  ami                    = "ami-0c55b159cbfafe1f0"  # Ubuntu 20.04 LTS AMI
  instance_type          = "t2.micro"
  key_name               = local.key_name  # Update with your SSH key name
  subnet_id              = data.aws_subnet.subnet_1.id  # Update with your subnet ID
  security_groups        = [aws_security_group.buildkite_sg.name]
  associate_public_ip_address = true

  tags = {
    Name = "buildkite-agent"
  }
  provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is available'"]

    connection {
    type        = "ssh"
    user        = local.ssh_user
    private_key = file(local.private_key_path)
    host        = self.public_ip
  }
  }
  
  provisioner "local-exec" {
    command = "ansible-playbook -i ${aws_instance.buildkite_instance.public_ip}, --private-key ${local.private_key_path} buildkite-agent.yml"
    
  }

}

# Output the public IP address of the instance
output "buildkite_instance_public_ip" {
  value = aws_instance.buildkite_instance.public_ip
}
