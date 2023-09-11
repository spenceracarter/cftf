variable "availability_zone_names" {
  type    = list(string)
  default = ["us-west-2a","us-west-2b"]
}

variable "main_vpc_cidr" {
    default = "10.1.0.0/16"
}

variable "public_subnets" {
    default = ["10.1.0.0/24","10.1.1.0/24"]
}

variable "private_subnets" {
    default = ["10.1.2.0/24","10.1.3.0/24"]
}

variable "db_subnets" {
    default = ["10.1.4.0/24","10.1.5.0/24"]
}
