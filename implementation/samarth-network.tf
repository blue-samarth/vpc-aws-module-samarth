# main.tf (or wherever you want to call the module)

module "samarth-network" {
  source = "../vpc"

  # Core VPC Configuration
  project_name    = var.project_name
  vpc_name        = var.vpc_name
  create_vpc      = var.create_vpc
  existing_vpc_id = var.existing_vpc_id
  vpc_cidr        = var.vpc_cidr

  # Subnet Configuration
  availability_zones = var.availability_zones
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  database_subnets   = var.database_subnets

  # Public IP Configuration
  map_public_ip_on_launch = var.map_public_ip_on_launch

  # NAT Gateway Configuration
  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  # Database Route Table Configuration
  create_database_route_table       = var.create_database_route_table
  create_database_nat_gateway_route = var.create_database_nat_gateway_route
  create_database_subnet_group      = var.create_database_subnet_group

  # Flow Logs Configuration
  enable_flow_logs                     = var.enable_flow_logs
  flow_logs_destination_type           = var.flow_logs_destination_type
  flow_logs_retention_in_days          = var.flow_logs_retention_in_days
  flow_logs_traffic_type               = var.flow_logs_traffic_type
  flow_logs_max_aggregation_interval   = var.flow_logs_max_aggregation_interval
  flow_logs_s3_bucket_arn              = var.flow_logs_s3_bucket_arn
  flow_logs_file_format                = var.flow_logs_file_format
  flow_logs_hive_compatible_partitions = var.flow_logs_hive_compatible_partitions
  flow_logs_per_hour_partition         = var.flow_logs_per_hour_partition

  # Jump Server Configuration
  deploy_jump_server        = var.deploy_jump_server
  key_name                  = var.key_name
  jump_server_instance_type = var.jump_server_instance_type
  jump_server_subnet_index  = var.jump_server_subnet_index
  allowed_ssh_cidrs         = var.allowed_ssh_cidrs

  # Tags
  tags = var.tags
}

# Root variables.tf - You need these variable declarations in your root module:

variable "project_name" {
  description = "Name of the project. Used in resource naming"
  type        = string
}

variable "vpc_name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
  default     = null
}

variable "create_vpc" {
  description = "Controls if VPC should be created (it affects almost all resources)"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of an existing VPC where resources will be created"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "The IPv4 CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "A list of availability zones names or ids in the region"
  type        = list(string)
  default     = []
}

variable "public_subnets" {
  description = "A list of public subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "A list of private subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "database_subnets" {
  description = "A list of database subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "map_public_ip_on_launch" {
  description = "Specify true to indicate that instances launched into the subnet should be assigned a public IP address"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Should be true to provision NAT Gateways for each of your private networks"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Should be true to provision a single shared NAT Gateway across all of your private networks"
  type        = bool
  default     = false
}

variable "one_nat_gateway_per_az" {
  description = "Should be true to provision NAT Gateways for each of your availability zones"
  type        = bool
  default     = false
}

variable "create_database_route_table" {
  description = "Controls if separate route table for database should be created"
  type        = bool
  default     = false
}

variable "create_database_nat_gateway_route" {
  description = "Controls if a nat gateway route should be created to give internet access to the database subnets"
  type        = bool
  default     = false
}

variable "create_database_subnet_group" {
  description = "Controls if database subnet group should be created"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Whether or not to enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "flow_logs_destination_type" {
  description = "Type of flow log destination. Can be s3 or cloud-watch-logs"
  type        = string
  default     = "cloud-watch-logs"
}

variable "flow_logs_retention_in_days" {
  description = "Specifies the number of days you want to retain log events in the specified log group for VPC flow logs"
  type        = number
  default     = 14
}

variable "flow_logs_traffic_type" {
  description = "The type of traffic to capture. Valid values: ACCEPT, REJECT, ALL"
  type        = string
  default     = "ALL"
}

variable "flow_logs_max_aggregation_interval" {
  description = "The maximum interval of time during which a flow of packets is captured and aggregated into a flow log record"
  type        = number
  default     = 600
}

variable "flow_logs_s3_bucket_arn" {
  description = "The ARN of the S3 bucket where VPC Flow Logs will be pushed"
  type        = string
  default     = null
}

variable "flow_logs_file_format" {
  description = "The format for the flow log. Default value: plain-text. Valid values: plain-text, parquet"
  type        = string
  default     = null
}

variable "flow_logs_hive_compatible_partitions" {
  description = "Indicates whether to use Hive-compatible prefixes for flow logs stored in Amazon S3"
  type        = bool
  default     = false
}

variable "flow_logs_per_hour_partition" {
  description = "Indicates whether to partition the flow log per hour"
  type        = bool
  default     = false
}

variable "deploy_jump_server" {
  description = "Whether to deploy a jump server (bastion host) in the public subnet"
  type        = bool
  default     = false
}

variable "key_name" {
  description = "The name of the AWS Key Pair to be used for the jump server"
  type        = string
  default     = null
}

variable "jump_server_instance_type" {
  description = "Instance type for the jump server"
  type        = string
  default     = "t2.micro"
}

variable "jump_server_subnet_index" {
  description = "Index of the public subnet where the jump server should be deployed"
  type        = number
  default     = null
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH to the jump server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}