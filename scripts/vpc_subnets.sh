#!/bin/bash

#========================
# VPC CIDR Configuration Wizard - Fixed Version with Better Error Messages
# Features: User-controlled placement, cushions, confirmation loop, descriptive errors
#========================

set -euo pipefail

# Colors
CYAN="\e[1;36m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
BLUE="\e[1;34m"
PURPLE="\e[1;35m"
RESET="\e[0m"

echo -e "${CYAN}=========================================="
echo -e "      VPC SUBNET Configuration Wizard       "
echo -e "         Enhanced with User Control         "
echo -e "==========================================${RESET}"

MENU_URL="https://raw.githubusercontent.com/blue-samarth/Terminal-Menu-Selector/master/menu_selector.sh"

# Check if menu_selector.sh is in the scripts folder
if [ ! -f "./scripts/menu_selector.sh" ]; then
  echo "[INFO] Downloading menu_selector to scripts folder..."
  curl -s -o "./scripts/menu_selector.sh" "$MENU_URL"
  chmod +x "./scripts/menu_selector.sh" 
  MENU_TOOL="./scripts/menu_selector.sh"
fi


if [ ! -f "$MENU_TOOL" ]; then
  echo "[INFO] Installing menu_selector..."
  sudo curl -s -o "$MENU_TOOL" "$MENU_URL"
  sudo chmod +x "$MENU_TOOL"
fi

source "$MENU_TOOL"

subnet_main() {
    local input_vpc_cidr="$1"
    
    # Helper function to convert IP to integer
    ip_to_int() {
        local ip="$1"
        IFS='.' read -r b1 b2 b3 b4 <<< "$ip"
        echo $(( (b1 << 24) + (b2 << 16) + (b3 << 8) + b4 ))
    }

    # Helper function to convert integer to IP
    int_to_ip() {
        local int="$1"
        local b1=$(((int >> 24) & 255))
        local b2=$(((int >> 16) & 255))
        local b3=$(((int >> 8) & 255))
        local b4=$((int & 255))
        echo "$b1.$b2.$b3.$b4"
    }

    # Enhanced validation with detailed error messages
    validate_ip_with_guidance() {
        local ip="$1"
        local base_ip="$2"
        local vpc_size="$3"
        local block_size="$4"
        local subnet_mask="$5"
        local group_name="$6"
        
        # Check if IP is within VPC range
        local ip_int=$(ip_to_int "$ip")
        local base_int=$(ip_to_int "$base_ip")
        local vpc_end_int=$((base_int + vpc_size - 1))
        
        if [ $ip_int -lt $base_int ] || [ $ip_int -gt $vpc_end_int ]; then
            echo -e "${RED}✗ ERROR: IP $ip is outside VPC range${RESET}"
            echo -e "${YELLOW}  VPC Range: $base_ip - $(int_to_ip $vpc_end_int)${RESET}"
            echo -e "${YELLOW}  Your IP: $ip${RESET}"
            echo -e "${GREEN}  Valid range for $group_name group: $base_ip to $(int_to_ip $((vpc_end_int - block_size)))${RESET}"
            return 1
        fi
        
        # Check alignment
        local remainder=$((ip_int % block_size))
        if [ $remainder -ne 0 ]; then
            echo -e "${RED}✗ ERROR: IP $ip must align to /$subnet_mask subnet boundaries${RESET}"
            echo -e "${YELLOW}  Block size: $block_size IPs${RESET}"
            echo -e "${YELLOW}  Your IP offset: $remainder (must be 0)${RESET}"
            echo -e "${GREEN}  Valid aligned IPs near $ip:${RESET}"
            
            # Show nearby valid options
            local aligned_down=$((ip_int - remainder))
            local aligned_up=$((aligned_down + block_size))
            
            [ $aligned_down -ge $base_int ] && echo -e "    • $(int_to_ip $aligned_down) (previous aligned)"
            [ $aligned_up -le $((vpc_end_int - block_size)) ] && echo -e "    • $(int_to_ip $aligned_up) (next aligned)"
            
            return 2
        fi
        
        # Check if there's enough space from this starting point
        local group_end_int=$((ip_int + block_size - 1))
        if [ $group_end_int -gt $vpc_end_int ]; then
            echo -e "${RED}✗ ERROR: Not enough space from $ip for $group_name group${RESET}"
            echo -e "${YELLOW}  Required: $block_size IPs${RESET}"
            echo -e "${YELLOW}  Available from $ip: $((vpc_end_int - ip_int + 1)) IPs${RESET}"
            echo -e "${GREEN}  Last valid starting IP: $(int_to_ip $((vpc_end_int - block_size + 1)))${RESET}"
            return 3
        fi
        
        return 0
    }

    # Check for overlaps between allocated groups with detailed messages
    check_overlap_with_guidance() {
        local new_start="$1"
        local new_size="$2"  
        local block_size="$3"
        local group_name="$4"
        local existing_allocation="$5"
        
        # If no existing allocation provided, no overlap
        if [[ -z "$existing_allocation" ]]; then
            return 0
        fi
        
        IFS=':' read -r existing_start existing_size existing_name <<< "$existing_allocation"
        
        local new_start_int=$(ip_to_int "$new_start")
        local new_end_int=$((new_start_int + (new_size * block_size) + block_size - 1)) # Include cushion
        local existing_start_int=$(ip_to_int "$existing_start")
        local existing_end_int=$((existing_start_int + (existing_size * block_size) + block_size - 1))
        
        # Check for overlap
        if [ $new_start_int -lt $existing_end_int ] && [ $new_end_int -gt $existing_start_int ]; then
            echo -e "${RED}✗ ERROR: $group_name group overlaps with $existing_name allocation${RESET}"
            echo -e "${YELLOW}  $group_name range: $new_start - $(int_to_ip $new_end_int) (with cushion)${RESET}"
            echo -e "${YELLOW}  $existing_name range: $existing_start - $(int_to_ip $existing_end_int) (with cushion)${RESET}"
            echo -e "${GREEN}  Suggestion: Start $group_name group at $(int_to_ip $existing_end_int) or later${RESET}"
            return 1
        fi
        return 0
    }

    echo -e "${BLUE}VPC CIDR provided: ${YELLOW}$input_vpc_cidr${RESET}\n"

    # Extract base IP and mask
    base_ip=$(echo "$input_vpc_cidr" | cut -d'/' -f1)
    mask_num=$(echo "$input_vpc_cidr" | cut -d'/' -f2)

    # Enhanced Guard Logic
    if [ "$mask_num" -ge 27 ]; then
        echo -e "${RED}[ERROR] VPC CIDR /$mask_num too small for meaningful subnetting.${RESET}"
        echo -e "${YELLOW}[INFO] For VPC /$mask_num, consider:${RESET}"
        echo -e "   • Using the VPC without subnetting"
        echo -e "   • Expanding VPC to /26 or larger"
        return 1
    fi

    # Calculate VPC parameters
    total_ips=$((2**(32 - mask_num)))
    available_bits=$((32 - mask_num))
    vpc_base_int=$(ip_to_int "$base_ip")
    vpc_end_int=$((vpc_base_int + total_ips - 1))
    
    echo -e "${GREEN}[INFO] VPC $input_vpc_cidr has $total_ips total IPs available.${RESET}"
    echo -e "${GREEN}[INFO] Available bits for subnetting: $available_bits${RESET}\n"

    echo -e "${PURPLE}Enhanced Subnetting Strategies (with cushions):${RESET}"
    echo -e "   • Automatic 1-block cushion between subnet groups"
    echo -e "   • User-controlled placement with smart defaults"
    echo -e "   • Preview and confirmation before final allocation"
    echo -e "${GREEN}==========================================${RESET}"

    # Strategy definitions with cushion-aware validation
    declare -a strategies=(
        "2:1 public, 1 private:Minimal setup:pub=1,prv=1"
        "3:1 public, 2 private:Basic multi-tier:pub=1,prv=2"
        "4:1 public, 3 private:Dev/staging environment:pub=1,prv=3"
        "4:1 public, 2 private, 1 database:3-tier application:pub=1,prv=2,db=1"
        "4:2 public, 2 private:HA across 2 AZs:pub=2,prv=2"
        "6:2 public, 2 private, 2 database:Full 3-tier HA:pub=2,prv=2,db=2"
        "8:Multi-AZ with redundancy:Enterprise setup:pub=4,prv=4"
        "9:3 public, 3 private, 3 database:Max HA across 3 AZs:pub=3,prv=3,db=3"
    )

    # Build valid options with cushion validation
    valid_options=()
    valid_metadata=()
    
    for strategy in "${strategies[@]}"; do
        IFS=':' read -r count desc detail types <<< "$strategy"
        
        # Count number of groups for cushion calculation
        groups=0
        [[ "$types" =~ "pub=" ]] && groups=$((groups + 1))
        [[ "$types" =~ "prv=" ]] && groups=$((groups + 1))
        [[ "$types" =~ "db=" ]] && groups=$((groups + 1))
        
        # Calculate effective required blocks (subnets + cushions)
        effective_required_blocks=$((count + groups - 1))
        
        # Calculate required bits for effective blocks
        required_bits=0
        temp=$effective_required_blocks
        while [ $temp -gt 1 ]; do
            temp=$((temp / 2))
            required_bits=$((required_bits + 1))
        done
        [ $((2**required_bits)) -lt $effective_required_blocks ] && required_bits=$((required_bits + 1))
        
        # Check if strategy fits in VPC
        available_blocks=$((2**(available_bits - required_bits)))
        [ $effective_required_blocks -gt $available_blocks ] && continue
        
        new_mask=$((mask_num + required_bits))
        [ $new_mask -gt 27 ] && continue
        
        ips_per_subnet=$((2**(32 - new_mask)))
        usable_ips=$((ips_per_subnet - 5))
        [ $usable_ips -lt 20 ] && continue
        
        warning=""
        [ $usable_ips -lt 30 ] && warning=" [Compact]"
        
        valid_options+=("$count Subnets - $desc (/$new_mask each - $usable_ips usable IPs)$warning")
        valid_metadata+=("$strategy")
    done
    
    valid_options+=("Custom Entry - Define your own subnet scheme")
    valid_metadata+=("custom:Custom:Coming soon:custom")

    if [ ${#valid_options[@]} -eq 1 ]; then
        echo -e "${RED}[ERROR] VPC too small for practical subnetting with cushions.${RESET}"
        return 1
    fi

    echo -e "${BLUE}Subnet Guide:${RESET}"
    echo -e "   • ${GREEN}[PUBLIC]${RESET} subnets host internet-facing resources"
    echo -e "   • ${BLUE}[PRIVATE]${RESET} subnets host internal resources"  
    echo -e "   • ${PURPLE}[DATABASE]${RESET} subnets host sensitive data stores\n"

    menu_selector "Choose a subnetting strategy:" choice "${valid_options[@]}"
    
    # Find selected index
    selected_idx=-1
    for i in "${!valid_options[@]}"; do
        if [[ "${valid_options[$i]}" == "$choice" ]]; then
            selected_idx=$i
            break
        fi
    done
    
    if [[ "$choice" == *"Custom Entry"* ]]; then
        echo -e "${YELLOW}[INFO] Custom subnet entry coming soon...${RESET}"
        VPC_CIDR="custom_pending"
        return 0
    fi
    
    # Parse selected strategy
    strategy_data="${valid_metadata[$selected_idx]}"
    IFS=':' read -r subnet_count desc detail type_hints <<< "$strategy_data"
    
    # Parse subnet types
    pub_count=0; prv_count=0; db_count=0
    IFS=',' read -ra pairs <<< "$type_hints"
    for pair in "${pairs[@]}"; do
        IFS='=' read -r type val <<< "$pair"
        case "$type" in
            "pub") pub_count=$val ;;
            "prv") prv_count=$val ;;
            "db") db_count=$val ;;
        esac
    done

    # Calculate subnet parameters
    groups=0
    [ $pub_count -gt 0 ] && groups=$((groups + 1))
    [ $prv_count -gt 0 ] && groups=$((groups + 1))
    [ $db_count -gt 0 ] && groups=$((groups + 1))
    
    effective_required_blocks=$((subnet_count + groups - 1))
    required_bits=0
    temp=$effective_required_blocks
    while [ $temp -gt 1 ]; do
        temp=$((temp / 2))
        required_bits=$((required_bits + 1))
    done
    [ $((2**required_bits)) -lt $effective_required_blocks ] && required_bits=$((required_bits + 1))
    
    subnet_mask=$((mask_num + required_bits))
    ips_per_subnet=$((2**(32 - subnet_mask)))
    block_size=$ips_per_subnet
    
    # User-controlled placement with confirmation loop
    confirmed=false
    while [ "$confirmed" = false ]; do
        echo -e "\n${CYAN}=== SUBNET PLACEMENT CONFIGURATION ===${RESET}"
        
        # Initialize placement variables
        declare -a group_starts=()
        declare -a group_allocations=()
        declare -a allocated_groups=()
        
        current_offset=0
        
        # Configure PUBLIC subnets
        if [ $pub_count -gt 0 ]; then
            default_start=$(int_to_ip $((vpc_base_int + current_offset)))
            echo -e "\n${GREEN}[PUBLIC GROUP] Configuration${RESET}"
            echo -e "Suggested start for PUBLIC group: ${YELLOW}$default_start${RESET}"
            
            menu_selector "Accept this default?" pub_choice "Yes" "No"
            
            if [ "$pub_choice" = "Yes" ]; then
                pub_start="$default_start"
            else
                echo -e "\n${CYAN}=== CUSTOM IP FOR PUBLIC GROUP ===${RESET}"
                echo -e "${YELLOW}Requirements:${RESET}"
                echo -e "  • Must be within VPC range: $base_ip - $(int_to_ip $vpc_end_int)"
                echo -e "  • Must align to /$subnet_mask boundaries (every $block_size IPs)"
                echo -e "${GREEN}Examples of valid aligned IPs:${RESET}"
                
                # Show some valid options
                local count=0
                for ((offset=0; offset<total_ips && count<8; offset+=block_size)); do
                    local candidate=$(int_to_ip $((vpc_base_int + offset)))
                    echo -e "  • $candidate"
                    count=$((count + 1))
                done
                
                while true; do
                    echo -e "\n${BLUE}Enter starting IP for PUBLIC group:${RESET}"
                    read -r pub_start
                    
                    if validate_ip_with_guidance "$pub_start" "$base_ip" "$total_ips" "$block_size" "$subnet_mask" "PUBLIC"; then
                        echo -e "${GREEN}✓ Valid IP: $pub_start${RESET}"
                        break
                    fi
                    echo -e "${YELLOW}Please try again with a valid IP.${RESET}"
                done
            fi
            
            group_starts+=("PUBLIC:$pub_start")
            allocated_groups+=("$pub_start:$pub_count:PUBLIC")
            current_offset=$(($(ip_to_int "$pub_start") - vpc_base_int + (pub_count + 1) * block_size))
        fi
        
        # Configure PRIVATE subnets
        if [ $prv_count -gt 0 ]; then
            default_start=$(int_to_ip $((vpc_base_int + current_offset)))
            echo -e "\n${BLUE}[PRIVATE GROUP] Configuration${RESET}"
            echo -e "Suggested start for PRIVATE group: ${YELLOW}$default_start${RESET}"
            
            menu_selector "Accept this default?" prv_choice "Yes" "No"
            
            if [ "$prv_choice" = "Yes" ]; then
                prv_start="$default_start"
            else
                echo -e "\n${CYAN}=== CUSTOM IP FOR PRIVATE GROUP ===${RESET}"
                echo -e "${YELLOW}Requirements: Must align to /$subnet_mask boundaries and not overlap with PUBLIC${RESET}"
                
                while true; do
                    echo -e "\n${BLUE}Enter starting IP for PRIVATE group:${RESET}"
                    read -r prv_start
                    
                    if validate_ip_with_guidance "$prv_start" "$base_ip" "$total_ips" "$block_size" "$subnet_mask" "PRIVATE"; then
                        # Check for overlap with PUBLIC
                        local overlap_found=false
                        for allocation in "${allocated_groups[@]}"; do
                            if [[ -n "$allocation" ]] && ! check_overlap_with_guidance "$prv_start" "$prv_count" "$block_size" "PRIVATE" "$allocation"; then
                                overlap_found=true
                                break
                            fi
                        done
                        
                        if [ "$overlap_found" = false ]; then
                            echo -e "${GREEN}✓ Valid IP: $prv_start${RESET}"
                            break
                        fi
                    fi
                    echo -e "${YELLOW}Please try again with a valid, non-overlapping IP.${RESET}"
                done
            fi
            
            group_starts+=("PRIVATE:$prv_start")
            allocated_groups+=("$prv_start:$prv_count:PRIVATE")
            current_offset=$(($(ip_to_int "$prv_start") - vpc_base_int + (prv_count + 1) * block_size))
        fi
        
        # Configure DATABASE subnets
        if [ $db_count -gt 0 ]; then
            default_start=$(int_to_ip $((vpc_base_int + current_offset)))
            echo -e "\n${PURPLE}[DATABASE GROUP] Configuration${RESET}"
            echo -e "Suggested start for DATABASE group: ${YELLOW}$default_start${RESET}"
            
            menu_selector "Accept this default?" db_choice "Yes" "No"
            
            if [ "$db_choice" = "Yes" ]; then
                db_start="$default_start"
            else
                echo -e "\n${CYAN}=== CUSTOM IP FOR DATABASE GROUP ===${RESET}"
                echo -e "${YELLOW}Requirements: Must align to /$subnet_mask boundaries and not overlap with existing groups${RESET}"
                
                while true; do
                    echo -e "\n${BLUE}Enter starting IP for DATABASE group:${RESET}"
                    read -r db_start
                    
                    if validate_ip_with_guidance "$db_start" "$base_ip" "$total_ips" "$block_size" "$subnet_mask" "DATABASE"; then
                        # Check for overlap with existing groups
                        local overlap_found=false
                        for allocation in "${allocated_groups[@]}"; do
                            if [[ -n "$allocation" ]] && ! check_overlap_with_guidance "$db_start" "$db_count" "$block_size" "DATABASE" "$allocation"; then
                                overlap_found=true
                                break
                            fi
                        done
                        
                        if [ "$overlap_found" = false ]; then
                            echo -e "${GREEN}✓ Valid IP: $db_start${RESET}"
                            break
                        fi
                    fi
                    echo -e "${YELLOW}Please try again with a valid, non-overlapping IP.${RESET}"
                done
            fi
            
            group_starts+=("DATABASE:$db_start")
            allocated_groups+=("$db_start:$db_count:DATABASE")
        fi
        
        # Generate preview
        echo -e "\n${CYAN}[PREVIEW] Proposed Allocation:${RESET}"
        subnets=()
        pub_allocations=()
        prv_allocations=()
        db_allocations=()
        
        # Generate PUBLIC subnets
        if [ $pub_count -gt 0 ]; then
            pub_start_int=$(ip_to_int "$pub_start")
            for ((i=0; i<pub_count; i++)); do
                subnet_ip=$(int_to_ip $((pub_start_int + i * block_size)))
                subnet="$subnet_ip/$subnet_mask"
                subnets+=("$subnet")
                pub_allocations+=("$subnet")
                usable=$((ips_per_subnet - 5))
                echo -e "  ${GREEN}[PUBLIC]${RESET}   $subnet ($usable usable IPs)"
            done
        fi
        
        # Generate PRIVATE subnets
        if [ $prv_count -gt 0 ]; then
            prv_start_int=$(ip_to_int "$prv_start")
            for ((i=0; i<prv_count; i++)); do
                subnet_ip=$(int_to_ip $((prv_start_int + i * block_size)))
                subnet="$subnet_ip/$subnet_mask"
                subnets+=("$subnet")
                prv_allocations+=("$subnet")
                usable=$((ips_per_subnet - 5))
                echo -e "  ${BLUE}[PRIVATE]${RESET}  $subnet ($usable usable IPs)"
            done
        fi
        
        # Generate DATABASE subnets
        if [ $db_count -gt 0 ]; then
            db_start_int=$(ip_to_int "$db_start")
            for ((i=0; i<db_count; i++)); do
                subnet_ip=$(int_to_ip $((db_start_int + i * block_size)))
                subnet="$subnet_ip/$subnet_mask"
                subnets+=("$subnet")
                db_allocations+=("$subnet")
                usable=$((ips_per_subnet - 5))
                echo -e "  ${PURPLE}[DATABASE]${RESET} $subnet ($usable usable IPs)"
            done
        fi
        
        echo -e "\n${YELLOW}Allocation Summary:${RESET}"
        echo -e "• Cushions: 1 block reserved between groups"
        echo -e "• Subnet mask: /$subnet_mask ($block_size IPs per subnet)"
        echo -e "• Usable IPs per subnet: $((ips_per_subnet - 5)) (excluding AWS reserved IPs)"
        
        # Confirmation with menu_selector
        echo -e "\n${YELLOW}Review the allocation above.${RESET}"
        menu_selector "Confirm this allocation?" confirm_choice "Yes" "No - Reconfigure"
        
        if [ "$confirm_choice" = "Yes" ]; then
            confirmed=true
        else
            echo -e "\n${BLUE}Let's reconfigure the placement...${RESET}"
            # Clear allocated groups for fresh start
            allocated_groups=()
        fi
    done

    # Generate structured output (format_v2)
    VPC_CIDR=$(IFS=, ; echo "${subnets[*]}")
    echo -e "\n${GREEN}[SUCCESS] Generated subnets: $VPC_CIDR${RESET}"
    
    # Export individual subnet type variables for external consumption
    if [ $pub_count -gt 0 ]; then
        # Convert array to Terraform list format: ["subnet1","subnet2","subnet3"]
        PUBLIC_SUBNETS="[$(printf '"%s",' "${pub_allocations[@]}" | sed 's/,$//')]"
        export PUBLIC_SUBNETS
        PUBLIC_SUBNET_COUNT="$pub_count"
        export PUBLIC_SUBNET_COUNT
    else
        PUBLIC_SUBNETS="[]"
        export PUBLIC_SUBNETS
        PUBLIC_SUBNET_COUNT="0"
        export PUBLIC_SUBNET_COUNT
    fi
    
    if [ $prv_count -gt 0 ]; then
        # Convert array to Terraform list format: ["subnet1","subnet2","subnet3"]
        PRIVATE_SUBNETS="[$(printf '"%s",' "${prv_allocations[@]}" | sed 's/,$//')]"
        export PRIVATE_SUBNETS
        PRIVATE_SUBNET_COUNT="$prv_count"
        export PRIVATE_SUBNET_COUNT
    else
        PRIVATE_SUBNETS="[]"
        export PRIVATE_SUBNETS
        PRIVATE_SUBNET_COUNT="0"
        export PRIVATE_SUBNET_COUNT
    fi
    
    if [ $db_count -gt 0 ]; then
        # Convert array to Terraform list format: ["subnet1","subnet2","subnet3"]
        DATABASE_SUBNETS="[$(printf '"%s",' "${db_allocations[@]}" | sed 's/,$//')]"
        export DATABASE_SUBNETS
        DATABASE_SUBNET_COUNT="$db_count"
        export DATABASE_SUBNET_COUNT
    else
        DATABASE_SUBNETS="[]"
        export DATABASE_SUBNETS
        DATABASE_SUBNET_COUNT="0"
        export DATABASE_SUBNET_COUNT
    fi
    
    # Enhanced structured output format_v2
    output="format_v2:Total_subnets:$subnet_count"
    
    if [ $pub_count -gt 0 ]; then
        pub_allocation_str=$(IFS=, ; echo "${pub_allocations[*]}")
        output="$output;pub_subnets:$pub_count;pub_start:$pub_start;pub_allocation:$pub_allocation_str"
    fi
    
    if [ $prv_count -gt 0 ]; then
        prv_allocation_str=$(IFS=, ; echo "${prv_allocations[*]}")
        output="$output;prv_subnets:$prv_count;prv_start:$prv_start;prv_allocation:$prv_allocation_str"
    fi
    
    if [ $db_count -gt 0 ]; then
        db_allocation_str=$(IFS=, ; echo "${db_allocations[*]}")
        output="$output;db_subnets:$db_count;db_start:$db_start;db_allocation:$db_allocation_str"
    fi
    
    output="$output;subnet_mask:/$subnet_mask;usable_ips_per_subnet:$((ips_per_subnet-5));confirmed:$confirmed"
    
    echo -e "\n${CYAN}[RESULT] $output${RESET}"
    
    # Debug output for exported variables
    echo -e "\n${BLUE}[EXPORTED VARIABLES]${RESET}"
    echo -e "${GREEN}PUBLIC_SUBNETS=${RESET}$PUBLIC_SUBNETS"
    echo -e "${GREEN}PUBLIC_SUBNET_COUNT=${RESET}$PUBLIC_SUBNET_COUNT"
    echo -e "${BLUE}PRIVATE_SUBNETS=${RESET}$PRIVATE_SUBNETS"
    echo -e "${BLUE}PRIVATE_SUBNET_COUNT=${RESET}$PRIVATE_SUBNET_COUNT"
    echo -e "${PURPLE}DATABASE_SUBNETS=${RESET}$DATABASE_SUBNETS"
    echo -e "${PURPLE}DATABASE_SUBNET_COUNT=${RESET}$DATABASE_SUBNET_COUNT"
    
    echo -e "\n${PURPLE}AWS Availability Zone Recommendations:${RESET}"
    if [ $subnet_count -le 3 ]; then
        echo -e "   • Deploy across 2 AZs for high availability"
    elif [ $subnet_count -le 6 ]; then
        echo -e "   • Deploy across 2-3 AZs for balanced redundancy"
    else
        echo -e "   • Deploy across 3 AZs for maximum high availability"
    fi
    
    echo -e "\n${GREEN}[SUCCESS] Enhanced subnet configuration complete with detailed guidance!${RESET}"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    subnet_main "10.0.0.0/16"
    echo "Final result: $VPC_CIDR"
fi