#!/bin/bash

#=========================================================
# Pragmatically Hardened VPC Configuration Generator
# Security improvements without over-engineering
#=========================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MENU_TOOL="./scripts/menu_selector.sh"
readonly TFVARS_FILE="terraform_network.tfvars"
readonly BACKUP_DIR="${SCRIPT_DIR}/backups"

# Simple logging
log() {
    local level="$1"
    shift
    echo "[$(date '+%H:%M:%S')] [$level] $*" >&2
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    exit "${2:-1}"
}

# Check menu_selector availability
check_menu_selector() {
    if [ ! -f "./scripts/menu_selector.sh" ]; then
      echo "[INFO] Downloading menu_selector to scripts folder..."
      curl -s -o "./scripts/menu_selector.sh" "$MENU_URL"
      chmod +x "./scripts/menu_selector.sh" 
      MENU_TOOL="./scripts/menu_selector.sh"
    fi
    if [[ ! -f "$MENU_TOOL" ]] || [[ ! -x "$MENU_TOOL" ]]; then
        error_exit "menu_selector not found or not executable at $MENU_TOOL. Please run bootstrap script first."
    fi
}

# Source menu_selector functions
source_menu_selector() {
    source "$MENU_TOOL"
}

# Backup existing configuration
backup_existing_config() {
    if [[ -f "$TFVARS_FILE" ]]; then
        mkdir -p "$BACKUP_DIR"
        local timestamp=$(date '+%Y%m%d_%H%M%S')_$$
        local backup_file="${BACKUP_DIR}/${TFVARS_FILE}.backup.${timestamp}"
        
        cp "$TFVARS_FILE" "$backup_file"
        log "INFO" "Existing configuration backed up to: $backup_file"
        
        echo "Existing $TFVARS_FILE found."
        read -r -p "Do you want to overwrite it? [y/N]: " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Configuration generation cancelled by user"
            exit 0
        fi
    fi
}

# Simple AZ validation and cleanup (permissive)
clean_availability_zones() {
    local azs_input="$1"
    
    # Just clean up whitespace and basic formatting
    echo "$azs_input" | sed 's/[[:space:]]//g' | sed 's/,+/,/g' | sed 's/^,//;s/,$//'
}

# Validate SSH CIDRs for security (critical security check)
validate_ssh_cidrs() {
    local cidrs_input="$1"
    
    if [[ -z "$cidrs_input" ]]; then
        log "ERROR" "SSH CIDRs cannot be empty for security reasons"
        return 1
    fi
    
    # Check for obviously insecure patterns
    if echo "$cidrs_input" | grep -qE "(0\.0\.0\.0/0|::/0)"; then
        log "WARN" "⚠️  SECURITY WARNING: Detected 0.0.0.0/0 - This allows SSH from anywhere on the internet!"
        read -r -p "Are you sure you want to allow SSH from anywhere? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Check for RFC5737 documentation ranges (likely copy-paste errors)
    if echo "$cidrs_input" | grep -qE "(203\.0\.113\.|198\.51\.100\.|192\.0\.2\.)"; then
        log "WARN" "⚠️  Detected RFC5737 documentation IP ranges (203.0.113.x, 198.51.100.x, 192.0.2.x)"
        log "WARN" "These are not routable on the internet and may be copy-paste errors."
        read -r -p "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Validate flow logs parameters (critical operational check)
validate_flow_logs_params() {
    local retention_days="$1"
    local aggregation_interval="$2"
    
    # Basic bounds checking for CloudWatch Logs
    if [[ $retention_days -lt 1 || $retention_days -gt 3653 ]]; then
        log "ERROR" "Flow logs retention days must be between 1 and 3653, got: $retention_days"
        return 1
    fi
    
    # AWS only supports these two values
    if [[ "$aggregation_interval" != "60" && "$aggregation_interval" != "600" ]]; then
        log "ERROR" "Flow logs aggregation interval must be 60 or 600 seconds, got: $aggregation_interval"
        return 1
    fi
    
    return 0
}

# Validate NAT strategy against subnet configuration (prevents expensive mistakes)
validate_nat_strategy() {
    local enable_nat="$1"
    local public_subnet_count="$2"
    
    if [[ "$enable_nat" == "true" && $public_subnet_count -eq 0 ]]; then
        log "ERROR" "NAT Gateway requires at least one public subnet, but no public subnets configured"
        log "INFO" "Either enable public subnets or disable NAT Gateway"
        return 1
    fi
    
    return 0
}

# Safe source with basic validation
safe_source() {
    local script_path="$1"
    local script_name="$2"
    
    if [[ ! -f "$script_path" ]]; then
        error_exit "$script_name script not found at $script_path"
    fi
    
    source "$script_path"
}

# Main execution
main() {
    log "INFO" "Starting VPC configuration generation"
    
    # Check dependencies and source menu_selector
    check_menu_selector
    source_menu_selector
    
    # Backup existing configuration
    backup_existing_config
    
    # Collect basic information
    log "INFO" "Collecting project configuration..."
    
    read -p "Project name [my-project]: " project_name
    project_name=${project_name:-my-project}
    
    read -p "Availability zones (comma-separated) [us-east-1a,us-east-1b,us-east-1c]: " azs_input
    azs_input=${azs_input:-"us-east-1a,us-east-1b,us-east-1c"}
    azs=$(clean_availability_zones "$azs_input")
    
    # VPC Creation Strategy
    vpc_creation_choice=""
    menu_selector "VPC Creation Strategy:" vpc_creation_choice \
        "Create new VPC" \
        "Use existing VPC"
    
    if [[ "$vpc_creation_choice" == "Create new VPC" ]]; then
        create_vpc="true"
        existing_vpc_id="null"
        
        safe_source "scripts/vpc_cidr.sh" "VPC CIDR"
        cidr_main
        vpc_cidr="$VPC_CIDR"
        log "INFO" "VPC CIDR set to $vpc_cidr"
    else
        create_vpc="false"
        read -p "Enter existing VPC ID: " existing_vpc_id
        
        if [[ -z "$existing_vpc_id" ]]; then
            error_exit "Existing VPC ID cannot be empty"
        fi
        
        log "INFO" "Fetching VPC CIDR for existing VPC..."
        
        # Try AWS CLI with fallback
        if command -v aws >/dev/null 2>&1; then
            log "INFO" "AWS CLI found - attempting automatic VPC CIDR fetch..."
            vpc_cidr_output=$(aws ec2 describe-vpcs --vpc-ids "$existing_vpc_id" --query 'Vpcs[0].CidrBlock' --output text 2>&1)
            aws_exit_code=$?
            
            if [[ $aws_exit_code -eq 0 && "$vpc_cidr_output" != "None" && -n "$vpc_cidr_output" ]]; then
                vpc_cidr="$vpc_cidr_output"
                log "INFO" "Retrieved VPC CIDR: $vpc_cidr"
            else
                if echo "$vpc_cidr_output" | grep -q "UnauthorizedOperation\|AccessDenied"; then
                    log "WARN" "AWS CLI lacks permissions to describe VPCs (check IAM permissions) - using manual input"
                elif echo "$vpc_cidr_output" | grep -q "InvalidVpcID\|does not exist"; then
                    log "WARN" "VPC ID '$existing_vpc_id' not found or invalid - using manual input"
                else
                    log "WARN" "AWS CLI call failed: $vpc_cidr_output - using manual input"
                fi
                read -p "Please enter the VPC CIDR manually [10.0.0.0/16]: " vpc_cidr
                vpc_cidr=${vpc_cidr:-10.0.0.0/16}
            fi
        else
            log "INFO" "AWS CLI not available (skipping automatic VPC CIDR fetch) - using manual input"
            read -p "Please enter the VPC CIDR for the existing VPC [10.0.0.0/16]: " vpc_cidr
            vpc_cidr=${vpc_cidr:-10.0.0.0/16}
        fi
    fi
    
    # Subnet Configuration (trust upstream validation)
    safe_source "scripts/vpc_subnets.sh" "subnet configuration"
    subnet_main "$vpc_cidr"
    
    public_subnets="$PUBLIC_SUBNETS"
    private_subnets="$PRIVATE_SUBNETS"
    database_subnets="$DATABASE_SUBNETS"
    
    public_subnet_count="$PUBLIC_SUBNET_COUNT"
    private_subnet_count="$PRIVATE_SUBNET_COUNT"
    database_subnet_count="$DATABASE_SUBNET_COUNT"
    
    log "INFO" "Subnet configuration: Public($public_subnet_count), Private($private_subnet_count), Database($database_subnet_count)"
    
    # NAT Gateway Strategy
    nat_choice=""
    menu_selector "Choose NAT Gateway strategy:" nat_choice \
        "Single NAT (cost effective)" \
        "One per AZ (high availability)" \
        "No NAT"
    
    case "$nat_choice" in
        "Single NAT (cost effective)")
            enable_nat_gateway="true"
            single_nat_gateway="true"
            one_nat_gateway_per_az="false"
            ;;
        "One per AZ (high availability)")
            enable_nat_gateway="true"
            single_nat_gateway="false"
            one_nat_gateway_per_az="true"
            ;;
        "No NAT")
            enable_nat_gateway="false"
            single_nat_gateway="false"
            one_nat_gateway_per_az="false"
            ;;
    esac
    
    # Critical validation: NAT strategy vs subnet config
    if ! validate_nat_strategy "$enable_nat_gateway" "$public_subnet_count"; then
        error_exit "Invalid NAT Gateway configuration"
    fi
    
    # Database Configuration
    db_route_table_choice=""
    menu_selector "Create separate database route table?" db_route_table_choice "Yes" "No"
    [[ "$db_route_table_choice" == "Yes" ]] && create_database_route_table="true" || create_database_route_table="false"
    
    db_nat_choice=""
    menu_selector "Allow database subnets internet access via NAT?" db_nat_choice "Yes" "No"
    [[ "$db_nat_choice" == "Yes" ]] && create_database_nat_gateway_route="true" || create_database_nat_gateway_route="false"
    
    db_subnet_group_choice=""
    menu_selector "Create database subnet group?" db_subnet_group_choice "Yes" "No"
    [[ "$db_subnet_group_choice" == "Yes" ]] && create_database_subnet_group="true" || create_database_subnet_group="false"
    
    # VPC Flow Logs
    flow_logs_choice=""
    menu_selector "Enable VPC Flow Logs?" flow_logs_choice "Yes" "No"
    [[ "$flow_logs_choice" == "Yes" ]] && enable_flow_logs="true" || enable_flow_logs="false"
    
    if [[ "$enable_flow_logs" == "true" ]]; then
        menu_selector "Select flow logs destination type:" flow_logs_destination_type "cloud-watch-logs" "s3"
        flow_logs_destination_type=${flow_logs_destination_type:-cloud-watch-logs}
        
        read -p "Flow logs retention in days [14]: " flow_logs_retention_in_days
        flow_logs_retention_in_days=${flow_logs_retention_in_days:-14}
        
        read -p "Flow logs max aggregation interval (60/600) [600]: " flow_logs_max_aggregation_interval
        flow_logs_max_aggregation_interval=${flow_logs_max_aggregation_interval:-600}
        
        # Critical validation: flow logs parameters
        if ! validate_flow_logs_params "$flow_logs_retention_in_days" "$flow_logs_max_aggregation_interval"; then
            error_exit "Invalid flow logs configuration"
        fi
        
        menu_selector "Select flow logs traffic type:" flow_logs_traffic_type "ALL" "ACCEPT" "REJECT"
        flow_logs_traffic_type=${flow_logs_traffic_type:-ALL}
        
        # S3-specific configuration
        if [[ "$flow_logs_destination_type" == "s3" ]]; then
            read -p "S3 bucket ARN for flow logs [leave empty to auto-create]: " flow_logs_s3_bucket_arn
            
            if [[ -z "$flow_logs_s3_bucket_arn" ]]; then
                log "INFO" "No S3 bucket ARN provided - Terraform module will auto-create bucket"
            fi
            
            menu_selector "Flow logs file format:" flow_logs_file_format "parquet" "plain-text"
            flow_logs_file_format=${flow_logs_file_format:-parquet}
            
            hive_partition_choice=""
            menu_selector "Use Hive-compatible partitions?" hive_partition_choice "Yes" "No"
            [[ "$hive_partition_choice" == "Yes" ]] && flow_logs_hive_compatible_partitions="true" || flow_logs_hive_compatible_partitions="false"
            
            hourly_partition_choice=""
            menu_selector "Enable per-hour partitioning?" hourly_partition_choice "Yes" "No"
            [[ "$hourly_partition_choice" == "Yes" ]] && flow_logs_per_hour_partition="true" || flow_logs_per_hour_partition="false"
        fi
    fi
    
    # Jump Server Configuration
    jump_choice=""
    menu_selector "Deploy Jump Server?" jump_choice "Yes" "No"
    [[ "$jump_choice" == "Yes" ]] && deploy_jump_server="true" || deploy_jump_server="false"
    
    if [[ "$deploy_jump_server" == "true" ]]; then
        # Critical check: jump server needs public subnets
        if [[ $public_subnet_count -eq 0 ]]; then
            log "WARN" "No public subnets configured. Jump server deployment not possible."
            log "INFO" "Setting deploy_jump_server to false and continuing..."
            deploy_jump_server="false"
        else
            read -p "Jump server key name [my-ec2-key-pair]: " key_name
            key_name=${key_name:-my-ec2-key-pair}
            
            menu_selector "Select jump server instance type:" jump_server_instance_type \
                "t3.micro : 1 GiB memory, 2 vCPUs" \
                "t3.small : 2 GiB memory, 2 vCPUs" \
                "t3.medium : 4 GiB memory, 2 vCPUs" \
                "t2.micro : 1 GiB memory, 1 vCPU" \
                "t2.small : 2 GiB memory, 1 vCPU" \
                -- "t3.micro" "t3.small" "t3.medium" "t2.micro" "t2.small"
            
            jump_server_instance_type=${jump_server_instance_type:-t3.micro}
            
            # Subnet selection with CIDR display
            if [[ $public_subnet_count -eq 1 ]]; then
                jump_server_subnet_index=0
                log "INFO" "Using the only available public subnet (index 0)"
            else
                echo "Found $public_subnet_count public subnets. Select jump server subnet:"
                
                # Extract CIDRs from PUBLIC_SUBNETS array format ["cidr1", "cidr2", ...]
                public_cidrs_clean=$(echo "$public_subnets" | sed 's/\[//;s/\]//;s/"//g;s/,/ /g')
                read -ra cidr_array <<< "$public_cidrs_clean"
                
                menu_options=()
                menu_values=()
                for i in $(seq 0 $((public_subnet_count - 1))); do
                    cidr="${cidr_array[$i]}"
                    menu_options+=("Public subnet $i ($cidr)")
                    menu_values+=("$i")
                done
                menu_selector "Select jump server public subnet:" jump_server_subnet_index "${menu_options[@]}" -- "${menu_values[@]}"
            fi
            
            # Critical security validation: SSH CIDRs
            while true; do
                read -p "Allowed SSH CIDRs (comma-separated) [10.0.0.0/16]: " allowed_ssh_cidrs
                allowed_ssh_cidrs=${allowed_ssh_cidrs:-10.0.0.0/16}
                if validate_ssh_cidrs "$allowed_ssh_cidrs"; then
                    break
                fi
                echo "Please enter valid SSH CIDRs."
            done
        fi
    fi
    
    # Resource Tags
    menu_selector "Select environment tag:" env_tag "development" "production" "staging" "testing" "custom"
    
    if [[ "$env_tag" == "custom" ]]; then
        read -p "Enter custom environment tag: " env_tag
    fi
    
    env_tag=${env_tag:-development}
    
    read -p "Owner tag [devops-team]: " owner_tag
    owner_tag=${owner_tag:-devops-team}
    
    # Generate terraform.tfvars
    log "INFO" "Generating $TFVARS_FILE..."
    
    # Prepare values for output
    [[ "$existing_vpc_id" == "null" ]] && existing_vpc_id_value="null" || existing_vpc_id_value="\"$existing_vpc_id\""
    
    # Generate clean AZ array for terraform (fixed parsing vulnerability)
    tf_azs="[\"$(echo "$azs" | sed 's/,/","/g')\"]"
    
    # Handle jump server values
    if [[ "$deploy_jump_server" == "true" ]]; then
        tf_ssh_cidrs="[\"$(echo "$allowed_ssh_cidrs" | sed 's/,/","/g')\"]"
        tf_key_name="\"$key_name\""
        tf_instance_type="\"$jump_server_instance_type\""
    else
        tf_ssh_cidrs="[]"
        tf_key_name="null"
        tf_instance_type="null"
        jump_server_subnet_index=0
    fi
    
    # Handle S3 flow logs parameters (proper null handling)
    if [[ "$enable_flow_logs" == "true" && "$flow_logs_destination_type" == "s3" ]]; then
        [[ -z "$flow_logs_s3_bucket_arn" ]] && s3_bucket_arn="null" || s3_bucket_arn="\"$flow_logs_s3_bucket_arn\""
        tf_file_format="\"$flow_logs_file_format\""
    else
        s3_bucket_arn="null"
        tf_file_format="null"
        flow_logs_hive_compatible_partitions="false"
        flow_logs_per_hour_partition="false"
    fi

    tmpfile="${TFVARS_FILE}.tmp"
    
    cat > "$tmpfile" <<EOF
# Terraform VPC Variables
# Generated on $(date '+%Y-%m-%d %H:%M:%S')
# Previous version backed up in: ${BACKUP_DIR}/

project_name = "$project_name"
vpc_name     = "${project_name}-vpc"

create_vpc      = $create_vpc
existing_vpc_id = $existing_vpc_id_value

vpc_cidr = "$vpc_cidr"

availability_zones = $tf_azs

public_subnets   = $public_subnets
private_subnets  = $private_subnets
database_subnets = $database_subnets

enable_nat_gateway     = $enable_nat_gateway
single_nat_gateway     = $single_nat_gateway
one_nat_gateway_per_az = $one_nat_gateway_per_az

enable_flow_logs                       = $enable_flow_logs
flow_logs_destination_type             = "$flow_logs_destination_type"
flow_logs_retention_in_days            = $flow_logs_retention_in_days
flow_logs_traffic_type                 = "$flow_logs_traffic_type"
flow_logs_max_aggregation_interval     = $flow_logs_max_aggregation_interval

deploy_jump_server        = $deploy_jump_server
key_name                  = $tf_key_name
jump_server_instance_type = $tf_instance_type
jump_server_subnet_index  = $jump_server_subnet_index
allowed_ssh_cidrs         = $tf_ssh_cidrs

map_public_ip_on_launch = true

create_database_route_table       = $create_database_route_table
create_database_nat_gateway_route = $create_database_nat_gateway_route
create_database_subnet_group      = $create_database_subnet_group

# S3 Flow Logs (only if S3 destination)
flow_logs_s3_bucket_arn              = $s3_bucket_arn
flow_logs_file_format                = $tf_file_format
flow_logs_hive_compatible_partitions = ${flow_logs_hive_compatible_partitions:-false}
flow_logs_per_hour_partition         = ${flow_logs_per_hour_partition:-false}

# Resource tags
tags = {
  Environment = "$env_tag"
  Project     = "$project_name"
  Owner       = "$owner_tag"
  ManagedBy   = "terraform"
  CreatedDate = "$(date +%Y-%m-%d)"
}
EOF
    mv "$tmpfile" "$TFVARS_FILE"

    log "INFO" "$TFVARS_FILE generated successfully!"
    log "INFO" "Summary: VPC($vpc_cidr), AZs($azs), Subnets(P:$public_subnet_count/Pr:$private_subnet_count/DB:$database_subnet_count), NAT($enable_nat_gateway), Jump($deploy_jump_server)"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi