#!/bin/bash

#========================
# VPC CIDR Configuration Wizard
#========================

# Colors
CYAN="\e[1;36m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
BLUE="\e[1;34m"
PURPLE="\e[1;35m"
RESET="\e[0m"

echo -e "${CYAN}=========================================="
echo -e "      VPC CIDR Configuration Wizard       "
echo -e "==========================================${RESET}"

MENU_TOOL="/usr/local/bin/menu_selector"
MENU_URL="https://raw.githubusercontent.com/blue-samarth/Kubernetes_automation/master/menu_selector.sh"

if [ ! -f "$MENU_TOOL" ]; then
  echo "[INFO] Installing menu_selector..."
  sudo curl -s -o "$MENU_TOOL" "$MENU_URL"
  sudo chmod +x "$MENU_TOOL"
fi

source "$MENU_TOOL"

cidr_main() {
    mask_options=(
        "/16 (255.255.0.0) - Enterprise Scale | 65,534 IPs | Perfect for large organizations"
        "/20 (255.255.240.0) - Production Ready | 4,094 IPs | Ideal for multi-tier applications" 
        "/24 (255.255.255.0) - Standard Choice | 254 IPs | Most common for small-medium workloads"
        "/28 (255.255.255.240) - Micro Networks | 14 IPs | Great for testing & development"
    )

    echo -e "${BLUE}Subnet Mask Guide:${RESET}"
    echo -e "   • Smaller numbers = More IPs available (e.g., /16 > /24)"
    echo -e "   • Consider future growth when choosing your mask"
    echo -e "   • AWS reserves 5 IPs per subnet for networking\n"

    menu_selector "Step 1: Choose your VPC Subnet Mask:" mask_choice "${mask_options[@]}"
    mask_num=$(echo "$mask_choice" | grep -o '/[0-9]*' | cut -d'/' -f2)
    echo -e "${GREEN}[INFO] Selected mask: /$mask_num${RESET}"

    # Clean first byte options without emojis
    first_byte_options=(
        "10.x.x.x - Class A Private | RFC 1918 | Most flexible, huge address space"
        "172.x.x.x - Class B Private | RFC 1918 | Medium networks, corporate standard"
        "192.x.x.x - Class C Private | RFC 1918 | Small networks, home/office use"
        "Manual Entry - Custom Range | Full control for advanced configurations"
    )

    echo -e "${BLUE}Private IP Ranges Explained:${RESET}"
    echo -e "   • 10.0.0.0/8    → 16.7M addresses (10.0.0.0 to 10.255.255.255)"
    echo -e "   • 172.16.0.0/12 → 1M addresses   (172.16.0.0 to 172.31.255.255)" 
    echo -e "   • 192.168.0.0/16 → 65K addresses (192.168.0.0 to 192.168.255.255)"
    echo -e "   • These ranges are never routed on the public internet\n"

    menu_selector "Step 2: Select your preferred private IP range:" first_byte_choice "${first_byte_options[@]}"

    # Extract the actual number from the choice
    if [[ "$first_byte_choice" == *"10.x.x.x"* ]]; then
        first_byte="10"
    elif [[ "$first_byte_choice" == *"172.x.x.x"* ]]; then
        first_byte="172"
    elif [[ "$first_byte_choice" == *"192.x.x.x"* ]]; then
        first_byte="192"
    else
        first_byte="Manual entry"
    fi

    echo -e "${GREEN}[INFO] Selected range: $first_byte${RESET}"

    # FIXED LOGIC - NO AUTO-COMPLETION FOR 172/192 UNLESS /16
    while true; do
        if [[ "$first_byte" == "10" ]]; then
            echo -e "${BLUE}For 10.x.x.x networks:${RESET}"
            echo -e "   • Common choices: 10.0.0.0, 10.1.0.0, 10.10.0.0"
            echo -e "   • Avoid conflicts with existing networks"
            echo -e "   • Consider using department codes (e.g., 10.100.0.0 for IT dept)\n"
            
            read -p "$(echo -e "${CYAN}Enter remaining bytes for 10.x.x.x/$mask_num (format: x.x.x):${RESET} ")" rest_bytes
            if [[ "$rest_bytes" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
                valid=true
                for octet in ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}; do
                    ((octet>=0 && octet<=255)) || valid=false
                done
                if $valid; then
                    vpc_cidr="10.${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}/$mask_num"
                    echo -e "${GREEN}Great choice! 10.x.x.x provides maximum flexibility${RESET}"
                    break
                fi
            fi
            echo -e "${RED}[ERROR] Invalid input. Each byte must be 0-255.${RESET}"
            
        elif [[ "$first_byte" == "172" ]]; then
            if [[ "$mask_num" == "16" ]]; then
                # Only auto-complete for /16
                vpc_cidr="172.16.0.0/16"
                echo -e "${GREEN}Excellent! 172.16.0.0/16 is widely used in enterprise environments${RESET}"
                break
            else
                # Ask for input for all other masks
                echo -e "${BLUE}For 172.16.x.x/$mask_num networks:${RESET}"
                echo -e "   • Common choices: 172.16.1.0, 172.16.10.0, 172.16.100.0"
                echo -e "   • Consider your network segmentation strategy\n"
                read -p "$(echo -e "${CYAN}Enter third and fourth bytes for 172.16.x.x/$mask_num (format: x.x):${RESET} ")" remaining_bytes
                
                if [[ "$remaining_bytes" =~ ^([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
                    valid=true
                    for octet in ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}; do
                        ((octet>=0 && octet<=255)) || valid=false
                    done
                    if $valid; then
                        vpc_cidr="172.16.${BASH_REMATCH[1]}.${BASH_REMATCH[2]}/$mask_num"
                        echo -e "${GREEN}Excellent choice! 172.16.x.x is a solid enterprise standard${RESET}"
                        break
                    fi
                fi
                echo -e "${RED}[ERROR] Invalid input. Each byte must be 0-255.${RESET}"
            fi
            
        elif [[ "$first_byte" == "192" ]]; then
            if [[ "$mask_num" == "16" ]]; then
                # Only auto-complete for /16
                vpc_cidr="192.168.0.0/16"
                echo -e "${GREEN}Perfect! 192.168.0.0/16 covers the entire Class C private range${RESET}"
                break
            else
                # Ask for input for all other masks
                echo -e "${BLUE}For 192.168.x.x/$mask_num networks:${RESET}"
                echo -e "   • Common choices: 192.168.1.0, 192.168.10.0, 192.168.100.0"
                echo -e "   • Avoid 192.168.1.x if you have home routers\n"
                read -p "$(echo -e "${CYAN}Enter third and fourth bytes for 192.168.x.x/$mask_num (format: x.x):${RESET} ")" remaining_bytes
                
                if [[ "$remaining_bytes" =~ ^([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
                    valid=true
                    for octet in ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}; do
                        ((octet>=0 && octet<=255)) || valid=false
                    done
                    if $valid; then
                        vpc_cidr="192.168.${BASH_REMATCH[1]}.${BASH_REMATCH[2]}/$mask_num"
                        echo -e "${GREEN}Perfect choice! 192.168.x.x is the classic home/office standard${RESET}"
                        break
                    fi
                fi
                echo -e "${RED}[ERROR] Invalid input. Each byte must be 0-255.${RESET}"
            fi
            
        else
            # Manual entry - accepts ANY valid IP format
            echo -e "${BLUE}Manual Entry Tips:${RESET}"
            echo -e "   • Enter just the IP address (we'll add /$mask_num automatically)"
            echo -e "   • Each octet must be between 0-255"
            echo -e "   • Consider using private ranges for security (10.x, 172.16-31.x, 192.168.x)\n"
            
            read -p "$(echo -e "${CYAN}Enter IP address (format: x.x.x.x):${RESET} ")" manual_ip
            
            # Only validate format and octet range - don't force private ranges
            if [[ "$manual_ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
                valid=true
                for octet in ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}; do
                    ((octet>=0 && octet<=255)) || valid=false
                done
                
                if $valid; then
                    vpc_cidr="$manual_ip/$mask_num"
                    
                    # Just inform about private vs public, but don't block
                    first_octet=${BASH_REMATCH[1]}
                    second_octet=${BASH_REMATCH[2]}
                    is_private=false
                    
                    if [[ $first_octet -eq 10 ]]; then
                        is_private=true
                        range_type="Class A Private (10.x.x.x)"
                    elif [[ $first_octet -eq 172 && $second_octet -ge 16 && $second_octet -le 31 ]]; then
                        is_private=true  
                        range_type="Class B Private (172.16-31.x.x)"
                    elif [[ $first_octet -eq 192 && $second_octet -eq 168 ]]; then
                        is_private=true
                        range_type="Class C Private (192.168.x.x)"
                    fi
                    
                    if $is_private; then
                        echo -e "${GREEN}Valid private IP range detected: $range_type${RESET}"
                    else
                        echo -e "${YELLOW}Note: This is a public IP range - ensure this is intentional${RESET}"
                    fi
                    echo -e "${GREEN}Final VPC CIDR: $vpc_cidr${RESET}"
                    break
                fi
            fi
            echo -e "${RED}[ERROR] Invalid IP format. Each octet must be 0-255.${RESET}"
        fi
    done

    # Calculate network info
    total_ips=$((2**(32-mask_num)))
    usable_ips=$((total_ips-5))

    echo -e "${GREEN}=========================================="
    echo -e "VPC CIDR Configuration Complete!"
    echo -e "==========================================${RESET}"
    echo -e "${PURPLE}Configuration Summary:${RESET}"
    echo -e "   VPC CIDR: ${CYAN}$vpc_cidr${RESET}"
    echo -e "   Total IP Addresses: ${YELLOW}$total_ips${RESET}"
    echo -e "   Usable IPs (after AWS reserves): ${YELLOW}$usable_ips${RESET}"
    echo -e "   Subnet Mask: ${YELLOW}/$mask_num${RESET}"

    if [[ $usable_ips -gt 1000 ]]; then
        echo -e "   Capacity: ${GREEN}Enterprise-scale network${RESET}"
    elif [[ $usable_ips -gt 200 ]]; then
        echo -e "   Capacity: ${GREEN}Production-ready network${RESET}"
    elif [[ $usable_ips -gt 50 ]]; then
        echo -e "   Capacity: ${GREEN}Standard network${RESET}"
    else
        echo -e "   Capacity: ${YELLOW}Development/testing network${RESET}"
    fi

    echo -e "${GREEN}------------------------------------------${RESET}"
    echo -e "${BLUE}Next Steps:${RESET}"
    echo -e "   1. Plan your subnet allocation within this CIDR"
    echo -e "   2. Consider availability zones for high availability"
    echo -e "   3. Reserve ranges for different tiers (web, app, db)"
    echo -e "${GREEN}==========================================${RESET}"

    # Export the VPC CIDR for use by calling scripts
    export VPC_CIDR="$vpc_cidr"
}

# If script is called directly (not sourced), run the function and echo result
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cidr_main
    echo "$VPC_CIDR"
fi