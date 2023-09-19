//Project ID Variable
variable "project_id" {
  type = string
  default = "temp-atanas"
}

//Region Variable
variable "region" {
  type = string
  description = "Region Name"
  default = "europe-central2"
}


//SQL Database Root Password
variable "root_pass" {
    type = string
    description = "Root Password For SQL Database"
    default = "123"
}

//SQL Database Name
variable "database" {
    type = string
    description = "SQL Database Name"
    default = "wpdb"
}

//SQL Database User
variable "db_user" {
    type = string
    description = "SQL Database User Name"
    default = "wpuser"
}

//SQL Databse User Password
variable "db_user_pass" {
    type = string
    description = "Passowrd for SQL Database User"
    default = "wppass"
}
