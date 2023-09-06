variable "availability_zone_names" {
  type    = list(string)
  default = ["us-west-1a","us-west-1b"]
}

variable "main_vpc_cidr" {
    default = "10.1.0.0/16"
}
