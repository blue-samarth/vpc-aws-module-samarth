############ CORE VPC OUTPUTS ############
output "vpc_id" {
  description = "ID of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].arn : null
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].cidr_block : var.vpc_cidr
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block of the VPC"
  value       = var.create_vpc && var.enable_ipv6 ? aws_vpc.main[0].ipv6_cidr_block : null
}

output "vpc_main_route_table_id" {
  description = "The ID of the main route table associated with this VPC"
  value       = var.create_vpc ? aws_vpc.main[0].main_route_table_id : null
}

output "vpc_default_network_acl_id" {
  description = "The ID of the default network ACL"
  value       = var.create_vpc ? aws_vpc.main[0].default_network_acl_id : null
}

output "vpc_default_security_group_id" {
  description = "The ID of the security group created by default on VPC creation"
  value       = var.create_vpc ? aws_vpc.main[0].default_security_group_id : null
}

############ SUBNET OUTPUTS ############
output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "List of ARNs of public subnets"
  value       = aws_subnet.public[*].arn
}

output "public_subnets_cidr_blocks" {
  description = "List of cidr_blocks of public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "public_subnets_ipv6_cidr_blocks" {
  description = "List of IPv6 cidr_blocks of public subnets in an IPv6 enabled VPC"
  value       = aws_subnet.public[*].ipv6_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_arns" {
  description = "List of ARNs of private subnets"
  value       = aws_subnet.private[*].arn
}

output "private_subnets_cidr_blocks" {
  description = "List of cidr_blocks of private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "private_subnets_ipv6_cidr_blocks" {
  description = "List of IPv6 cidr_blocks of private subnets in an IPv6 enabled VPC"
  value       = aws_subnet.private[*].ipv6_cidr_block
}

output "database_subnets" {
  description = "List of IDs of database subnets"
  value       = aws_subnet.database[*].id
}

output "database_subnet_arns" {
  description = "List of ARNs of database subnets"
  value       = aws_subnet.database[*].arn
}

output "database_subnets_cidr_blocks" {
  description = "List of cidr_blocks of database subnets"
  value       = aws_subnet.database[*].cidr_block
}

output "database_subnets_ipv6_cidr_blocks" {
  description = "List of IPv6 cidr_blocks of database subnets in an IPv6 enabled VPC"
  value       = aws_subnet.database[*].ipv6_cidr_block
}

output "database_subnet_group" {
  description = "ID of database subnet group"
  value       = local.len_database_subnets > 0 && var.create_database_subnet_group ? aws_db_subnet_group.database[0].id : null
}

output "database_subnet_group_name" {
  description = "Name of database subnet group"
  value       = local.len_database_subnets > 0 && var.create_database_subnet_group ? aws_db_subnet_group.database[0].name : null
}

############ INTERNET GATEWAY OUTPUTS ############
output "igw_id" {
  description = "The ID of the Internet Gateway"
  value       = local.len_public_subnets > 0 ? aws_internet_gateway.main[0].id : null
}

output "igw_arn" {
  description = "The ARN of the Internet Gateway"
  value       = local.len_public_subnets > 0 ? aws_internet_gateway.main[0].arn : null
}

output "egress_only_internet_gateway_id" {
  description = "The ID of the egress only Internet Gateway"
  value       = var.enable_ipv6 && local.len_private_subnets > 0 ? aws_egress_only_internet_gateway.main[0].id : null
}

############ NAT GATEWAY OUTPUTS ############
output "nat_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "nat_public_ips" {
  description = "List of public Elastic IPs created for AWS NAT Gateway"
  value       = aws_eip.nat[*].public_ip
}

output "natgw_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

############ ROUTE TABLE OUTPUTS ############
output "public_route_table_ids" {
  description = "List of IDs of the public route tables"
  value       = aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "List of IDs of the private route tables"
  value       = aws_route_table.private[*].id
}

output "database_route_table_ids" {
  description = "List of IDs of the database route tables"
  value       = aws_route_table.database[*].id
}

output "jump_server_route_table_id" {
  description = "ID of the jump server route table"
  value       = var.deploy_jump_server ? aws_route_table.jump_server[0].id : null
}

# Enhanced route table outputs for Transit Gateway integration
output "private_route_table_ids_by_az" {
  description = "Map of private route table IDs keyed by availability zone for Transit Gateway routing"
  value = {
    for i, rt in aws_route_table.private : local.availability_zones[i] => rt.id
  }
}

############ JUMP SERVER OUTPUTS ############
output "jump_server_instance_id" {
  description = "ID of the jump server EC2 instance"
  value       = var.deploy_jump_server ? aws_instance.jump_server[0].id : null
}

output "jump_server_instance_arn" {
  description = "ARN of the jump server EC2 instance"
  value       = var.deploy_jump_server ? aws_instance.jump_server[0].arn : null
}

output "jump_server_public_ip" {
  description = "Public IP address of the jump server"
  value       = var.deploy_jump_server ? aws_eip.jump_server[0].public_ip : null
}

output "jump_server_private_ip" {
  description = "Private IP address of the jump server"
  value       = var.deploy_jump_server ? aws_instance.jump_server[0].private_ip : null
}

output "jump_server_public_dns" {
  description = "Public DNS name of the jump server"
  value       = var.deploy_jump_server ? aws_instance.jump_server[0].public_dns : null
}

output "jump_server_private_dns" {
  description = "Private DNS name of the jump server"
  value       = var.deploy_jump_server ? aws_instance.jump_server[0].private_dns : null
}

output "jump_server_security_group_id" {
  description = "ID of the jump server security group"
  value       = var.deploy_jump_server ? aws_security_group.jump_server[0].id : null
}

output "jump_server_key_name" {
  description = "Key name of the jump server"
  value       = var.deploy_jump_server ? aws_instance.jump_server[0].key_name : null
}

############ DHCP OPTIONS OUTPUTS ############
output "dhcp_options_id" {
  description = "The ID of the DHCP options"
  value       = local.enable_dhcp_options ? aws_vpc_dhcp_options.main[0].id : null
}

############ VPC FLOW LOGS OUTPUTS ############
output "vpc_flow_log_id" {
  description = "The ID of the Flow Log resource"
  value       = var.enable_flow_logs ? aws_flow_log.vpc[0].id : null
}

output "vpc_flow_log_cloudwatch_iam_role_arn" {
  description = "The ARN of the IAM role for VPC Flow Log CloudWatch delivery"
  value       = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? aws_iam_role.flow_logs[0].arn : null
}

output "vpc_flow_log_cloudwatch_log_group_name" {
  description = "The name of the CloudWatch Log Group for VPC Flow Logs"
  value       = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}

############ AVAILABILITY ZONES OUTPUT ############
output "azs" {
  description = "A list of availability zones speficied as argument to this module"
  value       = local.availability_zones
}

############ ENVIRONMENT & METADATA OUTPUTS ############
output "environment" {
  description = "The environment name for this VPC"
  value       = var.project_name
}

output "environment_config" {
  description = "The environment configuration used for this VPC"
  value       = local.current_env_config
}

output "supported_environments" {
  description = "List of supported environments"
  value       = local.environments
}

output "name" {
  description = "The name of the VPC specified as argument to this module"
  value       = coalesce(var.vpc_name, "${var.project_name}-vpc")
}

############ COMPUTED VALUES ############
output "vpc_cidr_range" {
  description = "The CIDR range of the VPC for reference in other modules"
  value       = var.vpc_cidr
}

output "subnet_count" {
  description = "Total number of subnets created"
  value = {
    public   = local.len_public_subnets
    private  = local.len_private_subnets
    database = local.len_database_subnets
    total    = local.total_subnets
  }
}

output "nat_gateway_count" {
  description = "Number of NAT Gateways created"
  value       = var.enable_nat_gateway ? local.nat_gateway_count : 0
}

############ INTEGRATION OUTPUTS ############
# These outputs are useful for integration with other modules

output "all_subnets" {
  description = "All subnet IDs for easy integration"
  value = concat(
    aws_subnet.public[*].id,
    aws_subnet.private[*].id,
    aws_subnet.database[*].id
  )
}

output "all_subnet_cidrs" {
  description = "All subnet CIDR blocks"
  value = concat(
    aws_subnet.public[*].cidr_block,
    aws_subnet.private[*].cidr_block,
    aws_subnet.database[*].cidr_block
  )
}

output "subnets_by_type" {
  description = "Subnets grouped by type for easy reference"
  value = {
    public   = aws_subnet.public[*].id
    private  = aws_subnet.private[*].id
    database = aws_subnet.database[*].id
  }
}

# Useful for ALB creation
output "public_subnet_ids_string" {
  description = "Comma-separated string of public subnet IDs"
  value       = join(",", aws_subnet.public[*].id)
}

# Useful for Auto Scaling Groups
output "private_subnet_ids_string" {
  description = "Comma-separated string of private subnet IDs"
  value       = join(",", aws_subnet.private[*].id)
}
