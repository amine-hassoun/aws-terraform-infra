variable "common_tags" {
  type = map(string)
}

variable "table_name" {
  type    = string
  default = "items"
}

variable "read_capacity" {
  type    = number
  default = 5
}

variable "write_capacity" {
  type    = number
  default = 5
}