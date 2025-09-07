# Core VPC Configuration
variable "create_vpc" {
  description = "Controls if VPC should be created (it affects almost all resources)"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of an existing VPC where resources will be created (for example, if you have existing VPC)"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "The IPv4 CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
  default     = null
}

variable "project_name" {
  description = "Name of the project. Used in resource naming"
  type        = string
}

variable "env_name" {
  description = "Environment name (e.g., admin, development, production)"
  type        = string
  default     = null
}

variable "secondary_cidr_blocks" {
  description = "List of secondary CIDR blocks to associate with the VPC to extend the IP Address pool"
  type        = list(string)
  default     = []
}

# Subnet Configuration
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

variable "availability_zones" {
  description = "A list of availability zones names or ids in the region"
  type        = list(string)
  default     = []
}

variable "map_public_ip_on_launch" {
  description = "Specify true to indicate that instances launched into the subnet should be assigned a public IP address"
  type        = bool
  default     = true
}

# IPv6 Configuration
variable "enable_ipv6" {
  description = "Requests an Amazon-provided IPv6 CIDR block with a /56 prefix length for the VPC"
  type        = bool
  default     = false
}

variable "public_subnet_assign_ipv6_address_on_creation" {
  description = "Specify true to indicate that network interfaces created in the specified subnet should be assigned an IPv6 address"
  type        = bool
  default     = false
}

variable "private_subnet_assign_ipv6_address_on_creation" {
  description = "Specify true to indicate that network interfaces created in the specified subnet should be assigned an IPv6 address"
  type        = bool
  default     = false
}

variable "database_subnet_assign_ipv6_address_on_creation" {
  description = "Specify true to indicate that network interfaces created in the specified subnet should be assigned an IPv6 address"
  type        = bool
  default     = false
}

# NAT Gateway Configuration
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

# Route Table Configuration
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
  description = "Controls if database subnet group should be created (n.b. database_subnets must also be set)"
  type        = bool
  default     = true
}

# DHCP Options
variable "dhcp_options_domain_name" {
  description = "Specifies DNS name for DHCP options set (requires enable_dhcp_options set to true)"
  type        = string
  default     = null
}

variable "dhcp_options_domain_name_servers" {
  description = "Specify a list of DNS server addresses for DHCP options set, default to AWS provided (requires enable_dhcp_options set to true)"
  type        = list(string)
  default     = null
}

variable "dhcp_options_ntp_servers" {
  description = "Specify a list of NTP servers for DHCP options set (requires enable_dhcp_options set to true)"
  type        = list(string)
  default     = null
}

variable "dhcp_options_netbios_name_servers" {
  description = "Specify a list of netbios servers for DHCP options set (requires enable_dhcp_options set to true)"
  type        = list(string)
  default     = null
}

variable "dhcp_options_netbios_node_type" {
  description = "Specify netbios node_type for DHCP options set (requires enable_dhcp_options set to true)"
  type        = string
  default     = null
}

# Flow Logs Configuration
variable "enable_flow_logs" {
  description = "Whether or not to enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "flow_logs_destination_type" {
  description = "Type of flow log destination. Can be s3 or cloud-watch-logs"
  type        = string
  default     = "cloud-watch-logs"
  validation {
    condition     = contains(["s3", "cloud-watch-logs"], var.flow_logs_destination_type)
    error_message = "Flow logs destination type must be one of: s3, cloud-watch-logs."
  }
}

variable "flow_logs_retention_in_days" {
  description = "Specifies the number of days you want to retain log events in the specified log group for VPC flow logs"
  type        = number
  default     = 14
}

variable "flow_logs_s3_bucket_arn" {
  description = "The ARN of the S3 bucket where VPC Flow Logs will be pushed. If this ARN is a S3 bucket the appropriate permissions need to be set on that bucket's policy"
  type        = string
  default     = null
}

variable "flow_logs_log_format" {
  description = "The format of the flow log. You can use either the default format or a custom format"
  type        = string
  default     = null
}

variable "flow_logs_traffic_type" {
  description = "The type of traffic to capture. Valid values: ACCEPT, REJECT, ALL"
  type        = string
  default     = "ALL"
  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "Flow logs traffic type must be one of: ACCEPT, REJECT, ALL."
  }
}

variable "flow_logs_max_aggregation_interval" {
  description = "The maximum interval of time during which a flow of packets is captured and aggregated into a flow log record. Valid Values: 60 seconds or 600 seconds"
  type        = number
  default     = 600
  validation {
    condition     = contains([60, 600], var.flow_logs_max_aggregation_interval)
    error_message = "Flow logs max aggregation interval must be either 60 or 600 seconds."
  }
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
  description = "Indicates whether to partition the flow log per hour. This reduces the cost and response time for queries"
  type        = bool
  default     = false
}

# Tag Variables
variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "vpc_tags" {
  description = "Additional tags for the VPC"
  type        = map(string)
  default     = {}
}

variable "igw_tags" {
  description = "Additional tags for the internet gateway"
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Additional tags for the public subnets"
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags for the private subnets"
  type        = map(string)
  default     = {}
}

variable "database_subnet_tags" {
  description = "Additional tags for the database subnets"
  type        = map(string)
  default     = {}
}

variable "nat_eip_tags" {
  description = "Additional tags for the NAT EIP"
  type        = map(string)
  default     = {}
}

variable "nat_gateway_tags" {
  description = "Additional tags for the NAT gateways"
  type        = map(string)
  default     = {}
}

variable "public_route_table_tags" {
  description = "Additional tags for the public route tables"
  type        = map(string)
  default     = {}
}

variable "private_route_table_tags" {
  description = "Additional tags for the private route tables"
  type        = map(string)
  default     = {}
}

variable "database_route_table_tags" {
  description = "Additional tags for the database route tables"
  type        = map(string)
  default     = {}
}

variable "database_subnet_group_tags" {
  description = "Additional tags for the database subnet group"
  type        = map(string)
  default     = {}
}

variable "dhcp_options_tags" {
  description = "Additional tags for the DHCP option set"
  type        = map(string)
  default     = {}
}

# Jump Server Configuration
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

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH to the jump server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "jump_server_subnet_index" {
  description = "Index of the public subnet where the jump server should be deployed (0-based). If null, defaults to 0"
  type        = number
  default     = null
}

variable "jump_server_instance_type" {
  description = "Instance type for the jump server"
  type        = string
  default     = "t2.micro"
}