############ LOCALS ############
locals {
  len_public_subnets   = length(var.public_subnets)
  len_private_subnets  = length(var.private_subnets)
  len_database_subnets = length(var.database_subnets)

  max_subnets   = max(local.len_public_subnets, local.len_private_subnets, local.len_database_subnets)
  total_subnets = local.len_public_subnets + local.len_private_subnets + local.len_database_subnets

  availability_zones  = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, local.max_subnets)
  nat_gateway_count   = var.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(local.availability_zones) : local.len_public_subnets
  enable_dhcp_options = var.dhcp_options_domain_name != null || var.dhcp_options_domain_name_servers != null

  # Environment-based naming
  environments = ["admin", "development", "production", "staging"]
  
  environment_config = {
    admin = {
      enable_flow_logs = true
      enable_jump_server = true
      nat_gateway_required = false
    }
    production = {
      enable_flow_logs = true
      enable_jump_server = false
      nat_gateway_required = true
    }
    development = {
      enable_flow_logs = false
      enable_jump_server = false
      nat_gateway_required = true
    }
    staging = {
      enable_flow_logs = true
      enable_jump_server = false
      nat_gateway_required = true
    }
  }
  
  # Get current environment config (fallback to development if not found)
  filtered_environment_config = { 
    for env, cfg in local.environment_config :
    env => cfg if contains(local.environments, env)
  }
  
  # Current environment config based on project_name
  current_env_config = lookup(local.environment_config, var.project_name, local.environment_config.development)

  # Jump server configuration with defensive checks and environment logic
  enable_jump_server = (var.deploy_jump_server || local.current_env_config.enable_jump_server) && local.len_public_subnets > 0
  jump_subnet_index = var.deploy_jump_server ? (
    var.jump_server_subnet_index != null ? 
    min(var.jump_server_subnet_index, local.len_public_subnets - 1) : 0
  ) : 0

  # Enhanced validation checks
  subnet_count_valid         = local.total_subnets > 0
  az_count_sufficient        = length(local.availability_zones) >= local.max_subnets
  jump_server_requires_public = var.deploy_jump_server ? local.len_public_subnets > 0 : true
  jump_subnet_index_valid    = var.deploy_jump_server ? (
    var.jump_server_subnet_index == null || 
    (var.jump_server_subnet_index >= 0 && var.jump_server_subnet_index < local.len_public_subnets)
  ) : true
  
  key_name_provided_when_jump_server = var.deploy_jump_server ? var.key_name != null : true
  nat_gateway_configuration_valid = !(var.single_nat_gateway && var.one_nat_gateway_per_az)
  cidr_overlap_check = true
}


# Validation: Ensure we have subnets
resource "null_resource" "validate_subnets" {
  count = local.subnet_count_valid ? 0 : 1
  
  provisioner "local-exec" {
    command = "echo 'ERROR: At least one subnet type (public, private, or database) must be specified' && exit 1"
  }
}

# Validation: Ensure sufficient AZs
resource "null_resource" "validate_azs" {
  count = local.az_count_sufficient ? 0 : 1
  
  provisioner "local-exec" {
    command = "echo 'ERROR: Not enough availability zones for the number of subnets specified' && exit 1"
  }
}

# Validation: Jump subnet index is valid
resource "null_resource" "validate_jump_subnet_index" {
  count = local.jump_subnet_index_valid ? 0 : 1
  
  provisioner "local-exec" {
    command = "echo 'ERROR: Jump server subnet index is out of range for public subnets' && exit 1"
  }
}

############ DATA SOURCES ############
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

############ VPC ############
resource "aws_vpc" "main" {
  count = var.create_vpc ? 1 : 0

  cidr_block                           = var.vpc_cidr
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  assign_generated_ipv6_cidr_block     = var.enable_ipv6
  enable_network_address_usage_metrics = local.current_env_config.enable_flow_logs

  tags = merge(var.tags, var.vpc_tags, {
    Name                 = coalesce(var.vpc_name, "${var.project_name}-vpc")
    Environment          = var.project_name
    EnvironmentTier      = local.current_env_config.enable_flow_logs ? "monitored" : "standard"
    SupportedEnvironments = join(",", local.environments)
  })
}

locals {
  vpc_id = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
  
  # Main VPC reference for IPv6 CIDR blocks
  main_vpc = var.create_vpc && length(aws_vpc.main) > 0 ? aws_vpc.main[0] : null
}

############ SECONDARY CIDR BLOCKS ############
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  for_each = var.create_vpc ? toset(var.secondary_cidr_blocks) : toset([])

  vpc_id     = local.vpc_id
  cidr_block = each.value
}

############ DHCP OPTIONS ############
resource "aws_vpc_dhcp_options" "main" {
  count = local.enable_dhcp_options ? 1 : 0

  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers
  ntp_servers          = var.dhcp_options_ntp_servers
  netbios_name_servers = var.dhcp_options_netbios_name_servers
  netbios_node_type    = var.dhcp_options_netbios_node_type

  tags = merge(var.tags, var.dhcp_options_tags, {
    Name = "${var.project_name}-dhcp-options"
  })
}

resource "aws_vpc_dhcp_options_association" "main" {
  count = local.enable_dhcp_options ? 1 : 0

  vpc_id          = local.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.main[0].id
}

############ INTERNET GATEWAYS ############
resource "aws_internet_gateway" "main" {
  count = var.create_vpc && local.len_public_subnets > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(var.tags, var.igw_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_egress_only_internet_gateway" "main" {
  count = var.create_vpc && var.enable_ipv6 && local.len_private_subnets > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-eigw"
  })
}

############ PUBLIC SUBNETS ############
resource "aws_subnet" "public" {
  count = local.len_public_subnets

  vpc_id                          = local.vpc_id
  cidr_block                      = var.public_subnets[count.index]
  availability_zone               = element(local.availability_zones, count.index)
  map_public_ip_on_launch         = var.map_public_ip_on_launch
  assign_ipv6_address_on_creation = var.enable_ipv6 && var.public_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && var.create_vpc ? cidrsubnet(aws_vpc.main[0].ipv6_cidr_block, 8, count.index) : null

  tags = merge(var.tags, var.public_subnet_tags, {
    Name = "${var.project_name}-public-${element(local.availability_zones, count.index)}"
    Type = "Public"
    Tier = local.enable_jump_server && count.index == local.jump_subnet_index ? "Management" : "Web"
  })
}

############ PRIVATE SUBNETS ############
resource "aws_subnet" "private" {
  count = local.len_private_subnets

  vpc_id                          = local.vpc_id
  cidr_block                      = var.private_subnets[count.index]
  availability_zone               = element(local.availability_zones, count.index)
  assign_ipv6_address_on_creation = var.enable_ipv6 && var.private_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && var.create_vpc ? cidrsubnet(aws_vpc.main[0].ipv6_cidr_block, 8, count.index + local.len_public_subnets) : null

  tags = merge(var.tags, var.private_subnet_tags, {
    Name = "${var.project_name}-private-${element(local.availability_zones, count.index)}"
    Type = "Private"
    Tier = "Application"
  })
}

############ DATABASE SUBNETS ############
resource "aws_subnet" "database" {
  count = local.len_database_subnets

  vpc_id                          = local.vpc_id
  cidr_block                      = var.database_subnets[count.index]
  availability_zone               = element(local.availability_zones, count.index)
  assign_ipv6_address_on_creation = var.enable_ipv6 && var.database_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && var.create_vpc ? cidrsubnet(aws_vpc.main[0].ipv6_cidr_block, 8, count.index + local.len_public_subnets + local.len_private_subnets) : null

  tags = merge(var.tags, var.database_subnet_tags, {
    Name = "${var.project_name}-database-${element(local.availability_zones, count.index)}"
    Type = "Database"
    Tier = "Data"
  })
}

############ JUMP SERVER ############
resource "aws_security_group" "jump_server" {
  count = var.deploy_jump_server ? 1 : 0

  name        = "${var.project_name}-jump-server-sg"
  description = "Security group for jump server (bastion host)"
  vpc_id      = local.vpc_id

  # SSH inbound from allowed CIDRs
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access from allowed networks"
  }

  # SSH outbound to private networks (for jump server functionality)
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(var.private_subnets, var.database_subnets)
    description = "SSH access to private subnets"
  }

  # HTTPS outbound for package updates and AWS API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for updates and AWS API"
  }

  # HTTP outbound for package updates
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for package updates"
  }

  # DNS outbound
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS resolution"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-jump-server-sg"
  })
}

resource "aws_instance" "jump_server" {
  count = var.deploy_jump_server ? 1 : 0

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.jump_server_instance_type
  subnet_id              = aws_subnet.public[local.jump_subnet_index].id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.jump_server[0].id]

  # Enhanced monitoring and detailed monitoring
  monitoring = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-jump-server"
    Type = "BastionHost"
  })
}

resource "aws_eip" "jump_server" {
  count  = var.deploy_jump_server ? 1 : 0
  domain = "vpc"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-jump-server-eip"
  })
}

############ JUMP SERVER EIP ASSOCIATION ############
resource "aws_eip_association" "jump_server" {
  count         = var.deploy_jump_server ? 1 : 0
  instance_id   = aws_instance.jump_server[0].id

  allocation_id = aws_eip.jump_server[0].allocation_id
}


############ NAT GATEWAYS FOR PRIVATE SUBNETS ############
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0
  domain = "vpc"

  tags = merge(var.tags, var.nat_eip_tags, {
    Name = format("${var.project_name}-nat-eip-%s", element(local.availability_zones, var.single_nat_gateway ? 0 : count.index))
  })
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = element(aws_eip.nat[*].allocation_id, var.single_nat_gateway ? 0 : count.index)
  subnet_id     = element(aws_subnet.public[*].id, var.single_nat_gateway ? 0 : count.index)

  tags = merge(var.tags, var.nat_gateway_tags, {
    Name = format("${var.project_name}-nat-%s", element(local.availability_zones, var.single_nat_gateway ? 0 : count.index))
  })

  depends_on = [aws_internet_gateway.main]
}

############ ROUTE TABLES ############

# Public route table (shared by all public subnets except jump server)
resource "aws_route_table" "public" {
  count = local.len_public_subnets > 0 ? 1 : 0
  vpc_id = local.vpc_id

  tags = merge(var.tags, var.public_route_table_tags, {
    Name = "${var.project_name}-public-rt"
    Type = "Public"
  })
}

# Jump server route table (dedicated for jump server subnet)
resource "aws_route_table" "jump_server" {
  count = var.deploy_jump_server ? 1 : 0
  vpc_id = local.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-jump-server-rt"
    Type = "JumpServer"
  })
}

# Private route tables (one per AZ for HA)
resource "aws_route_table" "private" {
  count = local.len_private_subnets
  vpc_id = local.vpc_id

  tags = merge(var.tags, var.private_route_table_tags, {
    Name = format("${var.project_name}-private-rt-%s", element(local.availability_zones, count.index))
    Type = "Private"
  })
}

# Database route tables (optional, separate from private for network isolation)
resource "aws_route_table" "database" {
  count = var.create_database_route_table && local.len_database_subnets > 0 ? local.len_database_subnets : 0
  vpc_id = local.vpc_id

  tags = merge(var.tags, var.database_route_table_tags, {
    Name = format("${var.project_name}-database-rt-%s", element(local.availability_zones, count.index))
    Type = "Database"
  })
}

############ ROUTES ############

# Public subnet default route via IGW
resource "aws_route" "public_internet_gateway" {
  count = local.len_public_subnets > 0 && length(aws_internet_gateway.main) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id

  timeouts {
    create = "5m"
  }
}

# Jump server default route via IGW (direct internet access for bastion functionality)
resource "aws_route" "jump_server_internet_gateway" {
  count = var.deploy_jump_server && length(aws_internet_gateway.main) > 0 ? 1 : 0

  route_table_id         = aws_route_table.jump_server[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id

  timeouts {
    create = "5m"
  }
}

# Private subnet default routes via NAT (consistent HA routing)
resource "aws_route" "private_nat_gateway" {
  count = local.len_private_subnets > 0 && var.enable_nat_gateway ? local.len_private_subnets : 0

  route_table_id         = element(aws_route_table.private[*].id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.main[*].id, var.single_nat_gateway ? 0 : count.index)

  timeouts {
    create = "5m"
  }
}

# Database subnet routes (inherit from private if no dedicated route table)
resource "aws_route" "database_nat_gateway" {
  count = local.len_database_subnets > 0 && var.enable_nat_gateway && var.create_database_route_table ? local.len_database_subnets : 0

  route_table_id         = element(aws_route_table.database[*].id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.main[*].id, var.single_nat_gateway ? 0 : count.index)

  timeouts {
    create = "5m"
  }
}

# IPv6 routes for public subnets
resource "aws_route" "public_internet_gateway_ipv6" {
  count = var.enable_ipv6 && local.len_public_subnets > 0 && length(aws_internet_gateway.main) > 0 ? 1 : 0

  route_table_id              = aws_route_table.public[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.main[0].id

  timeouts {
    create = "5m"
  }
}

# IPv6 routes for jump server
resource "aws_route" "jump_server_internet_gateway_ipv6" {
  count = var.enable_ipv6 && var.deploy_jump_server && length(aws_internet_gateway.main) > 0 ? 1 : 0

  route_table_id              = aws_route_table.jump_server[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.main[0].id

  timeouts {
    create = "5m"
  }
}

# IPv6 egress for private subnets through Egress-Only IGW
resource "aws_route" "private_ipv6_egress" {
  count = var.enable_ipv6 && local.len_private_subnets > 0 && length(aws_egress_only_internet_gateway.main) > 0 ? local.len_private_subnets : 0

  route_table_id              = element(aws_route_table.private[*].id, count.index)
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.main[0].id
}

############ ROUTE TABLE ASSOCIATIONS ############

# Public subnets (exclude jump server subnet)
resource "aws_route_table_association" "public" {
  count = local.len_public_subnets

  subnet_id = element(aws_subnet.public[*].id, count.index)
  # Associate jump server subnet to its dedicated route table, others to public route table
  route_table_id = var.deploy_jump_server && count.index == local.jump_subnet_index ? aws_route_table.jump_server[0].id : aws_route_table.public[0].id
}

# Private subnets
resource "aws_route_table_association" "private" {
  count = local.len_private_subnets

  subnet_id      = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(aws_route_table.private[*].id, count.index)
}

# Database subnets
resource "aws_route_table_association" "database" {
  count = local.len_database_subnets > 0 ? local.len_database_subnets : 0

  subnet_id      = element(aws_subnet.database[*].id, count.index)
  route_table_id = var.create_database_route_table ? element(aws_route_table.database[*].id, count.index) : element(aws_route_table.private[*].id, count.index)
}

############ DATABASE SUBNET GROUP ############
resource "aws_db_subnet_group" "database" {
  count = local.len_database_subnets > 0 && var.create_database_subnet_group ? 1 : 0

  name       = lower("${var.project_name}-db-subnet-group")
  subnet_ids = aws_subnet.database[*].id

  tags = merge(var.tags, var.database_subnet_group_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

############ VPC FLOW LOGS ############
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? 1 : 0

  name              = "/aws/vpc/flowlogs/${var.project_name}"
  retention_in_days = var.flow_logs_retention_in_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? 1 : 0

  name = "${var.project_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? 1 : 0

  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn             = var.flow_logs_destination_type == "cloud-watch-logs" ? aws_iam_role.flow_logs[0].arn : null
  log_destination          = var.flow_logs_destination_type == "cloud-watch-logs" ? aws_cloudwatch_log_group.vpc_flow_logs[0].arn : var.flow_logs_s3_bucket_arn
  log_destination_type     = var.flow_logs_destination_type
  log_format               = var.flow_logs_log_format
  traffic_type             = var.flow_logs_traffic_type
  vpc_id                   = local.vpc_id
  max_aggregation_interval = var.flow_logs_max_aggregation_interval

  dynamic "destination_options" {
    for_each = var.flow_logs_destination_type == "s3" ? [1] : []
    content {
      file_format                = var.flow_logs_file_format
      hive_compatible_partitions = var.flow_logs_hive_compatible_partitions
      per_hour_partition         = var.flow_logs_per_hour_partition
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}