# ============================================================================
# MAIN TERRAFORM CONFIGURATION
# ============================================================================
# Note: Terraform version and provider configuration are in versions.tf and providers.tf

resource "aws_instance" "EC2Instance" {
    ami               = var.llm_host_ami
    instance_type     = var.llm_host_instance_type
    key_name          = var.key_pair_name
    availability_zone = var.availability_zone
    tenancy = "default"
    subnet_id = aws_subnet.EC2PrivateSubnet.id
    ebs_optimized = true
    vpc_security_group_ids = [
        aws_security_group.EC2SecurityGroup.id
    ]
    source_dest_check = true
    root_block_device {
        volume_size           = var.llm_host_volume_size
        volume_type           = "gp3"
        delete_on_termination = true
    }
    user_data = "IyEvYmluL2Jhc2gKc2V0IC1lCgojIEJhc2ljIHN5c3RlbSBzZXR1cApzdWRvIGFwdC1nZXQgdXBkYXRlCnN1ZG8gYXB0LWdldCB1cGdyYWRlIC15CnN1ZG8gYXB0LWdldCBpbnN0YWxsIC15IGN1cmwgZ2l0IG5naW54CgojIENyZWF0ZSBzY3JpcHRzIGRpcmVjdG9yeQpzdWRvIG1rZGlyIC1wIC9vcHQvc2NyaXB0cwpjZCAvb3B0L3NjcmlwdHMKCiMgV3JpdGUgY3JlYXRlLWdyb3VwLnNoCnN1ZG8gdGVlIGNyZWF0ZS1ncm91cC5zaCA+IC9kZXYvbnVsbCA8PCdDUkVBVEVfR1JPVVBfRU9GJwpzdWRvIHVzZXJhZGQgLXIgLXMgL2Jpbi9mYWxzZSAtbSAtZCAvdXNyL3NoYXJlL29sbGFtYSBvbGxhbWEKc3VkbyBta2RpciAtcCAvdXNyL3NoYXJlL29sbGFtYS8ub2xsYW1hL21vZGVscwpzdWRvIGNob3duIC1SIG9sbGFtYTpvbGxhbWEgL3Vzci9zaGFyZS9vbGxhbWEKQ1JFQVRFX0dST1VQX0VPRgoKIyBXcml0ZSBvbGxhbWEtc2VydmljZS5zaApzdWRvIHRlZSBvbGxhbWEtc2VydmljZS5zaCA+IC9kZXYvbnVsbCA8PCdPTExBTUFfU0VSVklDRV9FT0YnCiMhL2Jpbi9iYXNoCiMgVXBkYXRlIHNlcnZpY2Ugd2l0aCBzZWxmLWhlYWxpbmcgY29uZmlnCnN1ZG8gdGVlIC9ldGMvc3lzdGVtZC9zeXN0ZW0vb2xsYW1hLnNlcnZpY2UgPiAvZGV2L251bGwgPDwnRU9GJwpbVW5pdF0KRGVzY3JpcHRpb249T2xsYW1hIFNlcnZpY2UKQWZ0ZXI9bmV0d29yay1vbmxpbmUudGFyZ2V0CldhbnRzPW5ldHdvcmstb25saW5lLnRhcmdldAoKW1NlcnZpY2VdClR5cGU9c2ltcGxlCkV4ZWNTdGFydD0vdXNyL2xvY2FsL2Jpbi9vbGxhbWEgc2VydmUKVXNlcj1vbGxhbWEKR3JvdXA9b2xsYW1hClJlc3RhcnQ9YWx3YXlzClJlc3RhcnRTZWM9NQpTdGFydExpbWl0SW50ZXJ2YWw9MApNZW1vcnlMaW1pdD03RwpUaW1lb3V0U3RhcnRTZWM9NjAKRW52aXJvbm1lbnQ9Ik9MTEFNQV9IT1NUPTAuMC4wLjA6MTE0MzQiCkVudmlyb25tZW50PSJPTExBTUFfTU9ERUxTPS91c3Ivc2hhcmUvb2xsYW1hLy5vbGxhbWEvbW9kZWxzIgpFbnZpcm9ubWVudD0iT0xMQU1BX01BWF9MT0FERURfTU9ERUxTPTEiCkVudmlyb25tZW50PSJPTExBTUFfTlVNX1BBUkFMTEVMPTEiCgpbSW5zdGFsbF0KV2FudGVkQnk9bXVsdGktdXNlci50YXJnZXQKRU9GCgpzdWRvIHN5c3RlbWN0bCBkYWVtb24tcmVsb2FkCnN1ZG8gc3lzdGVtY3RsIHJlc3RhcnQgb2xsYW1hCgojIEFkZCBoZWFsdGhjaGVjayBzY3JpcHQKc3VkbyB0ZWUgL3Vzci9sb2NhbC9iaW4vb2xsYW1hLWhlYWx0aGNoZWNrLnNoID4gL2Rldi9udWxsIDw8J0VPRicKIyEvYmluL2Jhc2gKUkVTUE9OU0U9JChjdXJsIC1zIC1vIC9kZXYvbnVsbCAtdyAiJXhodHRwX2NvZGV9IiBodHRwOi8vbG9jYWxob3N0OjExNDM0L2FwaS90YWdzIC0tY29ubmVjdC10aW1lb3V0IDUgLS1tYXgtdGltZSAxMCkKaWYgWyAiJFJFU1BPTlNFIiAhPSAiMjAwIiBdOyB0aGVuCiAgICBlY2hvICIkKGRhdGUpOiBPbGxhbWEgdW5oZWFsdGh5LCByZXN0YXJ0aW5nLi4uIgogICAgc3lzdGVtY3RsIHJlc3RhcnQgb2xsYW1hCmZpCkVPRgoKc3VkbyBjaG1vZCAreCAvdXNyL2xvY2FsL2Jpbi9vbGxhbWEtaGVhbHRoY2hlY2suc2gKCiMgQWRkIHRvIGNyb24KKHN1ZG8gY3JvbnRhYiAtbCAyPi9kZXYvbnVsbDsgZWNobyAiKiAqICogKiAqIC91c3IvbG9jYWwvYmluL29sbGFtYS1oZWFsdGhjaGVjay5zaCA+PiAvdmFyL2xvZy9vbGxhbWEtaGVhbHRoY2hlY2subG9nIDI+JjEiKSB8IHN1ZG8gY3JvbnRhYiAtCgplY2hvICJTZWxmLWhlYWxpbmcgY29uZmlndXJlZCEiCk9MTEFNQV9TRVJWSUNFX0VPRgoKIyBXcml0ZSBuZ2lueC1ycC5zaApzdWRvIHRlZSBuZ2lueC1ycC5zaCA+IC9kZXYvbnVsbCA8PCdOR0lOWF9SUF9FT0YnCiMhL2Jpbi9iYXNoCgojIENyZWF0ZSBuZ2lueCBjb25maWcKc3VkbyB0ZWUgL2V0Yy9uZ2lueC9zaXRlcy1hdmFpbGFibGUvb2xsYW1hID4gL2Rldi9udWxsIDw8J0VPRicKc2VydmVyIHsKICAgIGxpc3RlbiA4MDsKICAgIHNlcnZlcl9uYW1lIF87CiAgICAKICAgICMgSGVhbHRoIGNoZWNrIGVuZHBvaW50IGZvciBBUEkgR2F0ZXdheQogICAgbG9jYXRpb24gL2hlYWx0aCB7CiAgICAgICAgYWNjZXNzX2xvZyBvZmY7CiAgICAgICAgcmV0dXJuIDIwMCAiaGVhbHRoeVxuIjsKICAgICAgICBhZGRfaGVhZGVyIENvbnRlbnQtVHlwZSB0ZXh0L3BsYWluOwogICAgfQogICAgCiAgICAjIE9sbGFtYSBBUEkgZW5kcG9pbnRzCiAgICBsb2NhdGlvbiAvYXBpLyB7CiAgICAgICAgcHJveHlfcGFzcyBodHRwOi8vMTI3LjAuMC4xOjExNDM0L2FwaS87CiAgICAgICAgcHJveHlfaHR0cF92ZXJzaW9uIDEuMTsKICAgICAgICBwcm94eV9zZXRfaGVhZGVyIEhvc3QgJGhvc3Q7CiAgICAgICAgcHJveHlfc2V0X2hlYWRlciBYLVJlYWwtSVAgJHJlbW90ZV9hZGRyOwogICAgICAgIHByb3h5X3NldF9oZWFkZXIgWC1Gb3J3YXJkZWQtRm9yICRwcm94eV9hZGRfeF9mb3J3YXJkZWRfZm9yOwogICAgICAgIAogICAgICAgICMgU3RyZWFtaW5nIHN1cHBvcnQKICAgICAgICBwcm94eV9idWZmZXJpbmcgb2ZmOwogICAgICAgIHByb3h5X2NhY2hlIG9mZjsKICAgICAgICAKICAgICAgICAjIFRpbWVvdXRzIGZvciBMTE0gcmVzcG9uc2VzCiAgICAgICAgcHJveHlfY29ubmVjdF90aW1lb3V0IDMwMHM7CiAgICAgICAgcHJveHlfc2VuZF90aW1lb3V0IDMwMHM7CiAgICAgICAgcHJveHlfcmVhZF90aW1lb3V0IDMwMHM7CiAgICB9Cn0KRU9GCgpzdWRvIGxuIC1zZiAvZXRjL25naW54L3NpdGVzLWF2YWlsYWJsZS9vbGxhbWEgL2V0Yy9uZ2lueC9zaXRlcy1lbmFibGVkLwpzdWRvIHJtIC1mIC9ldGMvbmdpbngvc2l0ZXMtZW5hYmxlZC9kZWZhdWx0CnN1ZG8gbmdpbnggLXQKc3VkbyBzeXN0ZW1jdGwgcmVzdGFydCBuZ2lueApzdWRvIHN5c3RlbWN0bCBlbmFibGUgbmdpbngKTkdJTlhfUlBfRU9GCgojIFdyaXRlIHRlc3QtZW5kcG9pbnQuc2gKc3VkbyB0ZWUgdGVzdC1lbmRwb2ludC5zaCA+IC9kZXYvbnVsbCA8PCdURVNUX0VORFBPSU5UX0VPRicKIyEvYmluL2Jhc2gKCmVjaG8gIlRlc3RpbmcgT2xsYW1hIEFQSSAvYXBpL3RhZ3MgZW5kcG9pbnQuLi4iClRBR1NfUkVTUE9OU0U9JChjdXJsIC1zIC1vIC9kZXYvbnVsbCAtdyAiJXhodHRwX2NvZGV9IiBodHRwOi8vbG9jYWxob3N0L2FwaS90YWdzKQppZiBbWyAiJFRBR1NfUkVTUE9OU0UiID09ICIyMDAiIF1dOyB0aGVuCiAgZWNobyAi4pyFIC9hcGkvdGFncyBlbmRwb2ludCByZWFjaGFibGUgKEhUVFAgMjAwKSIKZWxzZQogIGVjaG8gIuKdjCAvYXBpL3RhZ3MgZW5kcG9pbnQgcmV0dXJuZWQgSFRUUCAkVEFHU19SRVNQT05TRSIKZmkKCmVjaG8KZWNobyAiVGVzdGluZyBoZWFsdGggZW5kcG9pbnQgL2hlYWx0aC4uLiIKSEVBTFRIX1JFU1BPTlNFPSQoY3VybCAtcyAtbyAvZGV2L251bGwgLXcgIiV7aHR0cF9jb2RlfSIgaHR0cDovL2xvY2FsaG9zdC9oZWFsdGgpCmlmIFtbICIkSEVBTFRIX1JFU1BPTlNFIiA9PSAiMjAwIiBdXTsgdGhlbgogIGVjaG8gIuKchSAvaGVhbHRoIGVuZHBvaW50IHJlYWNoYWJsZSAoSFRUUCAyMDApIgplbHNlCiAgZWNobyAi4p2MIC9oZWFsdGggZW5kcG9pbnQgcmV0dXJuZWQgSFRUUCAkSEVBTFRIX1JFU1BPTlNFIgpmaQpURVNUX0VORFBPSU5UX0VPRgoKIyBXcml0ZSBzZXJ2ZXIuc2gKc3VkbyB0ZWUgc2VydmVyLnNoID4gL2Rldi9udWxsIDw8J1NFUlZFUl9FT0YnCiMhL2Jpbi9iYXNoCgouL29sbGFtYSBzZXJ2ZSA+IG91dHB1dC50eHQgMj4mMSAmIC4vb2xsYW1hIHJ1biBsbGFtYTMuMiAyPi9kZXYvbnVsbApTRVJWRVJfRU9GCgojIE1ha2UgYWxsIHNjcmlwdHMgZXhlY3V0YWJsZQpzdWRvIGNobW9kICt4IC9vcHQvc2NyaXB0cy8qLnNoCgojIExvZyBjb21wbGV0aW9uCmVjaG8gIkFsbCBzY3JpcHRzIGluc3RhbGxlZCB0byAvb3B0L3NjcmlwdHMiIHwgc3VkbyB0ZWUgLWEgL3Zhci9sb2cvdXNlci1kYXRhLmxvZwoK"
    tags = {
        Name = "llm-host"
    }
}

resource "aws_key_pair" "EC2KeyPair" {
    public_key = var.key_pair_public_key
    key_name   = var.key_pair_name
}


resource "aws_instance" "EC2Instance2" {
    ami               = var.bastion_ami
    instance_type     = var.bastion_instance_type
    key_name          = var.key_pair_name
    availability_zone = var.availability_zone
    tenancy = "default"
    subnet_id = aws_subnet.EC2PublicSubnet.id
    ebs_optimized = true
    vpc_security_group_ids = [
        aws_security_group.EC2BastionSecurityGroup.id
    ]
    source_dest_check = true
    root_block_device {
        volume_size           = var.bastion_volume_size
        volume_type           = "gp3"
        delete_on_termination = true
    }
    user_data = "IyEvYmluL2Jhc2gKYXB0LWdldCB1cGRhdGUKYXB0LWdldCB1cGdyYWRlIC15CmFwdC1nZXQgaW5zdGFsbCAteSBjdXJsIGdpdA=="
    tags = {
        Name = "bastion-host"
    }
}

resource "aws_security_group" "EC2SecurityGroup" {
    description = "LLM in private subnet"
    name = "llm-sg"
    tags = {}
    vpc_id = aws_vpc.EC2VPC.id
    ingress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = 80
        protocol = "tcp"
        to_port = 80
    }
    ingress {
        security_groups = [
            aws_security_group.EC2BastionSecurityGroup.id
        ]
        description = "Bastion"
        from_port = 8080
        protocol = "tcp"
        to_port = 8080
    }
    ingress {
        security_groups = [
            aws_security_group.EC2BastionSecurityGroup.id
        ]
        description = "Bastion"
        from_port = 22
        protocol = "tcp"
        to_port = 22
    }
    egress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = 0
        protocol = "-1"
        to_port = 0
    }
}

resource "aws_vpc" "EC2VPC" {
    cidr_block = var.vpc_cidr
    enable_dns_support = true
    enable_dns_hostnames = true
    instance_tenancy = "default"
    tags = {
        Name = "project-llm-vpc"
    }
}

resource "aws_internet_gateway" "EC2InternetGateway" {
    vpc_id = aws_vpc.EC2VPC.id
    tags = {
        Name = "project-llm-igw"
    }
}

resource "aws_subnet" "EC2PrivateSubnet" {
    vpc_id            = aws_vpc.EC2VPC.id
    cidr_block        = var.private_subnet_cidr
    availability_zone = var.availability_zone
    tags = {
        Name = "project-llm-private-subnet"
    }
}

resource "aws_subnet" "EC2PublicSubnet" {
    vpc_id                  = aws_vpc.EC2VPC.id
    cidr_block              = var.public_subnet_cidr
    availability_zone       = var.availability_zone
    map_public_ip_on_launch = true
    tags = {
        Name = "project-llm-public-subnet"
    }
}

resource "aws_route_table" "EC2PublicRouteTable" {
    vpc_id = aws_vpc.EC2VPC.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.EC2InternetGateway.id
    }
    tags = {
        Name = "project-llm-public-rt"
    }
}

resource "aws_route_table_association" "EC2PublicSubnetAssociation" {
    subnet_id = aws_subnet.EC2PublicSubnet.id
    route_table_id = aws_route_table.EC2PublicRouteTable.id
}

resource "aws_security_group" "EC2BastionSecurityGroup" {
    description = "Bastion host security group"
    name = "bastion-sg"
    vpc_id = aws_vpc.EC2VPC.id
    ingress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = 22
        protocol = "tcp"
        to_port = 22
    }
    egress {
        cidr_blocks = [
            "0.0.0.0/0"
        ]
        from_port = 0
        protocol = "-1"
        to_port = 0
    }
    tags = {
        Name = "bastion-sg"
    }
}
