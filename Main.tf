## Tried to put these in as modules, and kept running into the ever so lovely error that the directory was unreadable. If that weren't being an issue right now, I'd have each section in its own module and called appropriately.
### Build the VPC
locals {
    subnets = {
        for i, x in setproduct(["public","private","db"],["a","b"]) :
        "us-west-2${x[1]}-${x[0]}" =>
        {
            az      = "us-west-2${x[1]}"
            cidr    = cidrsubnet(var.main_vpc_cidr, 8, i)
            tags    = {
                Purpose = "${x[0]}"
            }
        }
    }
}
#Subnet section shamelessly stolen from https://stackoverflow.com/questions/75678808/creating-multiple-subnets-in-order-per-availability-zone-with-terraform

resource "aws_vpc" "main" {
    cidr_block       = var.main_vpc_cidr
    instance_tenancy = "default"
    enable_dns_hostnames = true
    enable_dns_support = true
}

resource aws_subnet "this" {
    for_each = local.subnets
    vpc_id = aws_vpc.main.id
    cidr_block = each.value.cidr
    availability_zone = each.value.az
    tags = each.value.tags
}

data aws_subnets publicsubnets {
    filter {
        name = "vpc-id"
        values = [aws_vpc.main.id]
    }
    filter {
        name = "tag:Purpose"
        values = ["public"]
    }
}

data aws_subnets privatesubnets {
    filter {
        name = "vpc-id"
        values = [aws_vpc.main.id]
    }
    filter {
        name = "tag:Purpose"
        values = ["private"]
    }
}

data aws_subnets dbsubnets {
    filter {
        name = "vpc-id"
        values = [aws_vpc.main.id]
    }
    filter {
        name = "tag:Purpose"
        values = ["db"]
    }
}

resource "aws_internet_gateway" "IGW" {
    vpc_id =  aws_vpc.main.id
}

resource "aws_eip" "nateIP" {
    vpc   = true
}

resource "aws_nat_gateway" "NATgw" {
   allocation_id = aws_eip.nateIP.id
   subnet_id = data.aws_subnets.publicsubnets.ids[0]
}

resource "aws_route_table" "PublicRT" {
   vpc_id = aws_vpc.main.id
   route {
       cidr_block = "0.0.0.0/0"
       nat_gateway_id = aws_internet_gateway.IGW.id
   }
}

resource "aws_route_table" "PrivateRT" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.NATgw.id
   }
}
resource "aws_route_table" "dbRT" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.NATgw.id
   }
}


resource "aws_route_table_association" "PublicRTassociation" {
    count = 2
    subnet_id = "${data.aws_subnets.publicsubnets.ids[count.index]}"
    route_table_id = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "PrivateRTassociation" {
    count = 2
    subnet_id = "${data.aws_subnets.privatesubnets.ids[count.index]}"
    route_table_id = aws_route_table.PrivateRT.id
}

resource "aws_route_table_association" "dbRTassociation" {
    count = 2
    subnet_id = "${data.aws_subnets.dbsubnets.ids[count.index]}"
    route_table_id = aws_route_table.PrivateRT.id
}
## End VPC

#Create Security Groups

resource "aws_security_group" "bastionsg" {
    name = "Bastion Security Group"
    description = "Secuirty group for the bastion hosts"
    vpc_id = aws_vpc.main.id

    ingress {
        description = "Oh man, I feel dirty about this, but wide open to the internet"
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "appsg" {
    name = "Application security group"
    description = "What it says on the tin"
    vpc_id = aws_vpc.main.id

    ingress {
        description = "ssh access from bastion host"
        from_port = "22"
        to_port = "22"
        protocol = "-1"
        security_groups = [aws_security_group.bastionsg.id]
        cidr_blocks = ["10.1.0.0/24","10.1.1.0/24"]
    }

    ingress {
        description = "HTTPS access"
        from_port = "443"
        to_port = "443"
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "dbsg" {
    name = "DB security group"
    description = "Access to the DB from the Bastion and App hosts"
    vpc_id = aws_vpc.main.id

    ingress {
        description = "db access from bastion hosts"
        from_port = "5432"
        to_port = "5433"
        protocol = "-1"
        security_groups = [aws_security_group.bastionsg.id]
        cidr_blocks = ["10.1.0.0/16","10.1.1.0/16"]
    }

    ingress {
        description = "db access from app hosts"
        from_port = "5432"
        to_port = "5433"
        protocol = "-1"
        security_groups = [aws_security_group.appsg.id]
        cidr_blocks = ["10.1.0.0/16","10.1.1.0/16"]
    }
}

## End Security Groups

## Build the Hosts

data "aws_ami" "windows_ami" {
    most_recent = true
    name_regex = "Windows_Server-2019-English-Core-Base-*"
    filter {
        name = "root-device-type"
        values = ["ebs"]
    }
    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}

data "aws_ami" "rhel_ami" {
    most_recent = true
    filter {
        name = "image-id"
        values = ["ami-00aa0673b34e3c150"]
    }
}
### Yes, this is a cheap cheat to use the AMI ID directly, but that was the only rhel ami I found that fit in the free tier.

resource "aws_instance" "bastions" {
    ami = data.aws_ami.windows_ami.id
    instance_type = "t3.micro" #I know the specs called for "t3a.medium", but I'm working within the free tier constraints
    availability_zone = "us-west-2a"
#    associate_public_ip_address = true
    subnet_id = "${data.aws_subnets.publicsubnets.ids[0]}"
    security_groups = ["${aws_security_group.bastionsg.id}"]
    root_block_device {
      delete_on_termination = true
      encrypted = true
      volume_size = 50
    }

    user_data = <<EOF
<powershell>
net user /add localadmin n5V&48iJhb
net localgroup administrators localadmin /add
Rename-Computer -NewName bastion1 -Force -Restart
</powershell>
EOF 
    # Normally, I'd not be using powershell to add the user, but given that I'm doing this in an environment with no extant configuration management tool in place, I'm doing it the ugly and dirty way.
}

resource "aws_instance" "app_instances" {
    count = 2
    ami = data.aws_ami.rhel_ami.id
    instance_type = "t3.micro" #Once again, free tier restriction
    subnet_id = "${data.aws_subnets.privatesubnets.ids[count.index]}"
    availability_zone = "${var.availability_zone_names[count.index]}"
    security_groups = ["${aws_security_group.appsg.id}"]
    root_block_device {
        delete_on_termination = true
        encrypted = true
        volume_size = 20
    }

    user_data = <<EOF
if [ $(ifconfig | grep "inet " | head -n1 | cut -d"." -f3) -eq 2 ] ; then hostname wpserver1 ; else hostname wpserver 2 ; fi
#And here's where the user configuration data would go, if it were needed for this instance.
EOF
}

resource "aws_db_subnet_group" "dbsggroup" {
    name = "dbsggroup"
    subnet_ids = ["${data.aws_subnets.dbsubnets.ids[0]}","${data.aws_subnets.dbsubnets.ids[1]}"]
}

resource "aws_db_parameter_group" "dbpg" {
    name = "dbpg"
    family = "postgres11"

    parameter {
        name = "log_connections"
        value = 1
    }
}

resource "aws_db_instance" "rdsdb" {
    identifier  = "rds1"
    instance_class = "db.t3.micro"
    allocated_storage = 5
    engine = "postgres"
    engine_version = "11"
    username = "db_user"
    password = "db_password" #once again, were this not for a test, I'd be using aws secrets manager for this, rather than having it straight in the code
    db_subnet_group_name = aws_db_subnet_group.dbsggroup.name
    parameter_group_name = aws_db_parameter_group.dbpg.name
    vpc_security_group_ids = ["${aws_security_group.dbsg.id}"]
    publicly_accessible = false
}

## End host build
