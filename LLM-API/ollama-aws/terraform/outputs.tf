# ============================================================================
# LOCALS - Structured Data Objects (OOP-like approach)
# ============================================================================

locals {
    # SSH Configuration
    ssh_config = {
        key_path = var.ssh_key_path
        user     = var.ssh_user
    }

    # Bastion Host Object
    bastion = {
        instance_id = aws_instance.EC2Instance2.id
        public_ip   = aws_instance.EC2Instance2.public_ip
        private_ip  = aws_instance.EC2Instance2.private_ip
        ssh = {
            direct = "ssh -i ${local.ssh_config.key_path} ${local.ssh_config.user}@${aws_instance.EC2Instance2.public_ip}"
            step1  = "ssh -i ${local.ssh_config.key_path} ${local.ssh_config.user}@${aws_instance.EC2Instance2.public_ip}"
        }
    }

    # LLM Host Object
    llm_host = {
        instance_id = aws_instance.EC2Instance.id
        public_ip   = aws_instance.EC2Instance.public_ip
        private_ip  = aws_instance.EC2Instance.private_ip
        ssh = {
            direct = "ssh -i ${local.ssh_config.key_path} -o ProxyCommand=\"ssh -i ${local.ssh_config.key_path} -W %h:%p ${local.ssh_config.user}@${local.bastion.public_ip}\" ${local.ssh_config.user}@${aws_instance.EC2Instance.private_ip}"
            step1  = "ssh -i ${local.ssh_config.key_path} ${local.ssh_config.user}@${local.bastion.public_ip}"
            step2  = "ssh -i ${local.ssh_config.key_path} ${local.ssh_config.user}@${aws_instance.EC2Instance.private_ip}"
        }
    }

    # Key Pair Object
    key_pair = {
        name = aws_key_pair.EC2KeyPair.key_name
        id   = aws_key_pair.EC2KeyPair.id
    }

    # Service Endpoints Object
    services = {
        endpoints = {
            health = "http://${local.llm_host.private_ip}/health"
            api    = "http://${local.llm_host.private_ip}/api"
            direct = "http://${local.llm_host.private_ip}:11434/api"
        }
        check_commands = {
            bastion = <<-EOT
                # SSH to bastion first:
                ${local.bastion.ssh.direct}
                
                # Then run these commands:
                sudo systemctl status nginx
                sudo systemctl status ssh
                curl -s http://localhost/health || echo "No health endpoint on bastion"
            EOT
            llm_host = <<-EOT
                # SSH to LLM host via bastion:
                ${local.llm_host.ssh.direct}
                
                # Or connect in two steps:
                # Step 1: ${local.llm_host.ssh.step1}
                # Step 2: ${local.llm_host.ssh.step2}
                
                # Then run these commands:
                sudo systemctl status ollama
                sudo systemctl status nginx
                curl -s http://localhost/health
                curl -s http://localhost/api/tags
                curl -s http://localhost:11434/api/tags
                /opt/scripts/test-endpoint.sh
                sudo journalctl -u ollama -n 50
                sudo tail -f /var/log/ollama-healthcheck.log
            EOT
            quick = <<-EOT
                # From your local machine, run:
                ssh -i ${local.ssh_config.key_path} ${local.ssh_config.user}@${local.bastion.public_ip} "ssh -i ${local.ssh_config.key_path} ${local.ssh_config.user}@${local.llm_host.private_ip} 'curl -s http://localhost/health && echo && curl -s http://localhost/api/tags | head -20'"
            EOT
        }
    }

    # Network Object
    network = {
        vpc = {
            id   = aws_vpc.EC2VPC.id
            cidr = aws_vpc.EC2VPC.cidr_block
        }
        subnets = {
            private = {
                id = aws_subnet.EC2PrivateSubnet.id
            }
            public = {
                id = aws_subnet.EC2PublicSubnet.id
            }
        }
        security_groups = {
            llm_host = aws_security_group.EC2SecurityGroup.id
            bastion  = aws_security_group.EC2BastionSecurityGroup.id
        }
    }
}

# ============================================================================
# OUTPUTS - Reference Structured Objects
# ============================================================================

# Bastion Host Outputs
output "bastion" {
    description = "Bastion host information"
    value = {
        instance_id = local.bastion.instance_id
        public_ip   = local.bastion.public_ip
        private_ip  = local.bastion.private_ip
        ssh_command = local.bastion.ssh.direct
    }
}

# LLM Host Outputs
output "llm_host" {
    description = "LLM host information"
    value = {
        instance_id   = local.llm_host.instance_id
        public_ip     = local.llm_host.public_ip
        private_ip    = local.llm_host.private_ip
        ssh = {
            direct    = local.llm_host.ssh.direct
            step1     = local.llm_host.ssh.step1
            step2     = local.llm_host.ssh.step2
        }
    }
}

# Key Pair Outputs
output "key_pair" {
    description = "EC2 key pair information"
    value = {
        name = local.key_pair.name
        id   = local.key_pair.id
    }
}

# Service Endpoints Outputs
output "services" {
    description = "Service endpoints and check commands"
    value = {
        endpoints = local.services.endpoints
        commands  = local.services.check_commands
    }
}

# Network Outputs
output "network" {
    description = "Network infrastructure information"
    value = {
        vpc             = local.network.vpc
        subnets         = local.network.subnets
        security_groups = local.network.security_groups
    }
}

# ============================================================================
# CONVENIENCE OUTPUTS (for backward compatibility and easy access)
# ============================================================================

output "bastion_public_ip" {
    description = "Public IP address of the bastion host"
    value       = local.bastion.public_ip
}

output "bastion_ssh_command" {
    description = "SSH command to connect to the bastion host"
    value       = local.bastion.ssh.direct
}

output "llm_host_private_ip" {
    description = "Private IP address of the LLM host"
    value       = local.llm_host.private_ip
}

output "llm_host_ssh_command" {
    description = "SSH command to connect to the LLM host via bastion"
    value       = local.llm_host.ssh.direct
}

output "llm_health_endpoint" {
    description = "Health check endpoint URL"
    value       = local.services.endpoints.health
}

output "llm_api_endpoint" {
    description = "Ollama API endpoint URL (via nginx)"
    value       = local.services.endpoints.api
}

# ============================================================================
# SUMMARY OUTPUT
# ============================================================================

output "summary" {
    description = "Complete infrastructure summary"
    value = <<-EOT
        ============================================
        LLM API Infrastructure Connection Summary
        ============================================
        
        BASTION HOST:
          Public IP:  ${local.bastion.public_ip}
          Private IP: ${local.bastion.private_ip}
          SSH:        ${local.bastion.ssh.direct}
        
        LLM HOST:
          Private IP: ${local.llm_host.private_ip}
          SSH Direct: ${local.llm_host.ssh.direct}
          SSH Step 1: ${local.llm_host.ssh.step1}
          SSH Step 2: ${local.llm_host.ssh.step2}
        
        SERVICE ENDPOINTS (from LLM host):
          Health:     ${local.services.endpoints.health}
          API:        ${local.services.endpoints.api}
          Direct:     ${local.services.endpoints.direct}
        
        KEY PAIR:
          Name:       ${local.key_pair.name}
          ID:         ${local.key_pair.id}
        
        NETWORK:
          VPC ID:     ${local.network.vpc.id}
          VPC CIDR:   ${local.network.vpc.cidr}
        
        ============================================
    EOT
}
