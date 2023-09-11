module "subnets" {
    source = "./modules"
}

data "aws_vpc" "main" {
    cidr_block  = var.main_vpc_cidr 
}

data "aws_subnets" "pubsubs" {
    filter {
        name    = "vpc-id"
        values  = [data.aws_vpc.main.id]
    }
    filter {
        name    = "tag:Purpose"
        values  = ["public"]
    }
}

data "aws_subnets" "prisubs" {
    filter {
        name    = "vpc-id"
        values  = [data.aws_vpc.main.id]
    }
    filter {
        name    = "tag:Purpose"
        values  = ["private"]
    }
}

data "aws_subnets" "dbsubs" {
    filter {
        name    = "vpc-id"
        values  = [data.aws_vpc.main.id]
    }
    filter {
        name    = "tag:Purpose"
        values  = ["db"]
    }
}

resource "aws_internet_gateway" "IGW" {
    vpc_id      = data.aws_vpc.main.id
}

resource "aws_eip" "nateIP" {
    domain      = "vpc"
}

resource "aws_nat_gateway" "NATgw" {
    allocation_id   = aws_eip.nateIP.id
    subnet_id       = data.aws_subnets.pubsubs.ids[1]
}

resource "aws_route_table" "PublicRT" {
    vpc_id       = data.aws_vpc.main.id
    route {
       cidr_block   = "0.0.0.0/0"
       gateway_id   = aws_internet_gateway.IGW.id
    }
    tags        = {
        Name    = "PublicRT"
    }
}

resource "aws_route_table" "PrivateRT" {
    vpc_id      = data.aws_vpc.main.id
    route {
       cidr_block      = "0.0.0.0/0"
       nat_gateway_id  = aws_nat_gateway.NATgw.id
    }
    tags        = {
        Name    = "PrivateRT"
    }
}
resource "aws_route_table" "dbRT" {
    vpc_id      = data.aws_vpc.main.id
    route {
        cidr_block      = "0.0.0.0/0"
        nat_gateway_id  = aws_nat_gateway.NATgw.id
    }
    tags        = {
        Name    = "dbRT"
    }
}
resource "aws_route_table_association" "PublicRTassociation" {
    for_each        = toset(data.aws_subnets.pubsubs.ids)
    subnet_id       = each.value
    route_table_id  = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "PrivateRTassociation" {
    for_each        = toset(data.aws_subnets.prisubs.ids)
    subnet_id       = each.value
    route_table_id  = aws_route_table.PrivateRT.id
}

resource "aws_route_table_association" "dbRTassociation" {
    for_each        = toset(data.aws_subnets.dbsubs.ids)
    subnet_id       = each.value
    route_table_id  = aws_route_table.dbRT.id
}
## End VPC

#Create Security Groups

resource "aws_security_group" "bastionsg" {
    name        = "Bastion Security Group"
    description = "Secuirty group for the bastion hosts"
    vpc_id      = "${data.aws_vpc.main.id}"

    ingress {
        description = "Oh man, I feel dirty about this, but wide open to the internet"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "appsg" {
    name        = "Application security group"
    description = "What it says on the tin"
    vpc_id      = "${data.aws_vpc.main.id}"

    ingress {
        description     = "ssh access from bastion host"
        from_port       = "22"
        to_port         = "22"
        protocol        = "tcp"
        security_groups = [aws_security_group.bastionsg.id]
        cidr_blocks     = ["10.1.0.0/24","10.1.1.0/24"]
    }

    ingress {
        description = "HTTPS access"
        from_port   = "443"
        to_port     = "443"
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

resource "aws_security_group" "dbsg" {
    name        = "DB security group"
    description = "Access to the DB from the Bastion and App hosts"
    vpc_id      = "${data.aws_vpc.main.id}"

    ingress {
        description     = "db access from bastion and app hosts"
        from_port       = "5432"
        to_port         = "5433"
        protocol        = "tcp"
        security_groups = [aws_security_group.bastionsg.id]
        cidr_blocks     = ["10.1.0.0/24","10.1.1.0/24","10.1.2.0/24","10.1.3.0/24"]
    }
}
    
## End Security Groups

## Build the Hosts

data "aws_ami" "windows_ami" {
    most_recent = true
    name_regex  = "Windows_Server-2019-English-Core-Base-*"
    filter {
        name    = "root-device-type"
        values  = ["ebs"]
    }
    filter {
        name    = "virtualization-type"
        values  = ["hvm"]
    }
}

data "aws_ami" "rhel_ami" {
    most_recent = true
    filter {
        name    = "image-id"
        values  = ["ami-00aa0673b34e3c150"]
    }
}
### Yes, this is a cheap cheat to use the AMI ID directly, but that was the only rhel ami I found that fit in the free tier.

resource "aws_instance" "bastions" {
    for_each                    = toset(data.aws_subnets.pubsubs.ids)
    ami                         = data.aws_ami.windows_ami.id
    instance_type               = "t3.micro" #I know the specs called for "t3a.medium", but I'm working within the free tier constraints
    associate_public_ip_address = true
    subnet_id                   = each.value
    key_name                    = "default"
    security_groups             = ["${aws_security_group.bastionsg.id}"]
    root_block_device {
      delete_on_termination = true
      encrypted             = true
      volume_size           = 50
    }
    tags                        = {
        Name    = "BastionHost"
    }

    user_data = <<EOF
<powershell>
net user /add localadmin n5V!48iJhb
net localgroup administrators localadmin /add
Rename-Computer -NewName bastion1 -Force -Restart
</powershell>
EOF 
    # Normally, I'd not be using powershell to add the user, but given that I'm doing this in an environment with no extant configuration management tool in place, I'm doing it the ugly and dirty way.
}

resource "aws_instance" "app_instance" {
    for_each            = toset(data.aws_subnets.prisubs.ids)
    ami                 = data.aws_ami.rhel_ami.id
    instance_type       = "t3.micro" #Once again, free tier restriction
    subnet_id           = each.value
    key_name            = "default"
    security_groups     = ["${aws_security_group.appsg.id}"]
    root_block_device {
        delete_on_termination   = true
        encrypted               = true
        volume_size             = 20
    }
    tags                = {
        Name    = "AppInstance"
    }

    user_data = <<EOF
if [ $(ifconfig | grep "inet " | head -n1 | cut -d"." -f3) -eq 2 ] ; then hostname wpserver1 ; else hostname wpserver 2 ; fi
#And here's where the user configuration data would go, if it were needed for this instance.
EOF
}

resource "aws_db_subnet_group" "dbsggroup" {
    name        = "dbsggroup"
    subnet_ids  = flatten(data.aws_subnets.dbsubs.ids)
}

resource "aws_db_parameter_group" "dbpg" {
    name        = "dbpg"
    family      = "postgres11"

    parameter {
        name    = "log_connections"
        value   = 1
    }
}

resource "aws_db_instance" "rdsdb" {
    identifier              = "rds1"
    instance_class          = "db.t3.micro"
    allocated_storage       = 5
    engine                  = "postgres"
    engine_version          = "11"
    username                = "db_user"
    password                = "db_password" #once again, were this not for a test, I'd be using aws secrets manager for this, rather than having it straight in the code
    db_subnet_group_name    = aws_db_subnet_group.dbsggroup.name
    parameter_group_name    = aws_db_parameter_group.dbpg.name
    vpc_security_group_ids  = ["${aws_security_group.dbsg.id}"]
    publicly_accessible     = false
    skip_final_snapshot     = true
}

## End host build

## Create ALB 

resource "aws_lb" "applb" {
    name                = "ApplicationLB"
    load_balancer_type  = "application"
    security_groups     = [aws_security_group.bastionsg.id]
    subnets             = flatten(data.aws_subnets.pubsubs.ids)
}

resource "aws_lb_target_group" "applbtg" {
    name        = "ApplicationLbTargetGroup"
    port        = "80" #Would be 443 for https, but no SSL Cert in my test environ
    protocol    = "HTTP" #Should be HTTPS, but same as above
    vpc_id      = data.aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "applbtga" {
    for_each            = aws_instance.app_instance
    target_group_arn    = aws_lb_target_group.applbtg.arn
    target_id           = each.value.id
    port                = "80"
}

resource "aws_lb_listener" "lbears" {
    load_balancer_arn   = aws_lb.applb.arn
    port                = "80"
    protocol            = "HTTP"
    default_action {
        type                = "forward"
        target_group_arn    = aws_lb_target_group.applbtg.arn
    }
}
