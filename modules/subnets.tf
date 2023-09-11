### Build the VPC
variable "main_vpc_cidr" {
    default = "10.1.0.0/16"
}

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
    cidr_block              = var.main_vpc_cidr
    instance_tenancy        = "default"
    enable_dns_hostnames    = true
    enable_dns_support      = true
}

resource aws_subnet "this" {
    for_each            = local.subnets
    vpc_id              = aws_vpc.main.id
    cidr_block          = each.value.cidr
    availability_zone   = each.value.az
    tags                = each.value.tags
}
