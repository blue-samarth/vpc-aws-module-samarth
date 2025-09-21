#!/bin/bash

#==============================================================================
# UNIVERSAL MENU SELECTOR - Production Release
#==============================================================================
# Author: blue-Samarth
# Version: 1.0.0
# License: MIT
#==============================================================================

set -euo pipefail

detect_terminal_capabilities() {
    local capabilities=""
    
    if [[ -t 1 ]]; then
        capabilities+="interactive "
    fi
    
    if [[ $TERM == *"color"* ]] || [[ $TERM == "xterm"* ]] || [[ $TERM == "screen"* ]]; then
        capabilities+="ansi "
    fi
    
    if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
        if (( $(tput colors 2>/dev/null || echo 0) >= 8 )); then
            capabilities+="tput_colors "
        fi
        if tput cup 0 0 >/dev/null 2>&1; then
            capabilities+="cursor_movement "
        fi
    fi
    
    if echo | read -rsn1 -t 0.1 >/dev/null 2>&1; then
        capabilities+="read_timeout "
    fi
    
    case "$(uname -s)" in
        Darwin) capabilities+="macos " ;;
        Linux) 
            if grep -qi microsoft /proc/version 2>/dev/null; then
                capabilities+="wsl "
            else
                capabilities+="linux "
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*) capabilities+="windows_bash " ;;
    esac
    
    # Fix: Check if TERM_PROGRAM is set before using it
    if [[ -n "${TERM_PROGRAM:-}" ]]; then
        if [[ $TERM_PROGRAM == "Apple_Terminal" ]]; then
            capabilities+="apple_terminal "
        elif [[ $TERM_PROGRAM == "iTerm.app" ]]; then
            capabilities+="iterm2 "
        fi
    fi
    
    if [[ $TERM == "screen"* ]] && [[ -n "${TMUX:-}" ]]; then
        capabilities+="tmux "
    fi
    
    echo "$capabilities"
}

setup_colors() {
    local capabilities="$1"
    
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE=""
    BOLD="" UNDERLINE="" REVERSE="" RESET="" NC=""
    
    if [[ $capabilities == *"tput_colors"* ]]; then
        RED=$(tput setaf 1 2>/dev/null)
        GREEN=$(tput setaf 2 2>/dev/null)
        YELLOW=$(tput setaf 3 2>/dev/null)
        BLUE=$(tput setaf 4 2>/dev/null)
        MAGENTA=$(tput setaf 5 2>/dev/null)
        CYAN=$(tput setaf 6 2>/dev/null)
        WHITE=$(tput setaf 7 2>/dev/null)
        BOLD=$(tput bold 2>/dev/null)
        UNDERLINE=$(tput smul 2>/dev/null)
        REVERSE=$(tput rev 2>/dev/null)
        RESET=$(tput sgr0 2>/dev/null)
        NC=$RESET
        return 0
    fi
    
    if [[ $capabilities == *"ansi"* ]] || [[ $capabilities == *"wsl"* ]] || [[ $TERM == *"color"* ]] || [[ $COLORTERM == "truecolor" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        BLUE='\033[0;34m'
        MAGENTA='\033[0;35m'
        CYAN='\033[0;36m'
        WHITE='\033[0;37m'
        BOLD='\033[1m'
        UNDERLINE='\033[4m'
        REVERSE='\033[7m'
        RESET='\033[0m'
        NC=$RESET
        return 0
    fi
    
    return 1
}

cursor_up() {
    local lines=${1:-1}
    local capabilities="$2"
    
    if [[ $capabilities == *"cursor_movement"* ]]; then
        tput cuu "$lines" 2>/dev/null
    elif [[ $capabilities == *"ansi"* ]] || [[ $capabilities == *"wsl"* ]]; then
        printf '\033[%dA' "$lines"
    fi
}

cursor_clear_line() {
    local capabilities="$1"
    
    if [[ $capabilities == *"cursor_movement"* ]]; then
        tput el 2>/dev/null
    elif [[ $capabilities == *"ansi"* ]] || [[ $capabilities == *"wsl"* ]]; then
        printf '\033[K'
    fi
}

hide_cursor() {
    local capabilities="$1"
    
    if [[ $capabilities == *"cursor_movement"* ]]; then
        tput civis 2>/dev/null
    elif [[ $capabilities == *"ansi"* ]] || [[ $capabilities == *"wsl"* ]]; then
        printf '\033[?25l'
    fi
}

show_cursor() {
    local capabilities="$1"
    
    if [[ $capabilities == *"cursor_movement"* ]]; then
        tput cnorm 2>/dev/null
    elif [[ $capabilities == *"ansi"* ]] || [[ $capabilities == *"wsl"* ]]; then
        printf '\033[?25h'
    fi
}

function advanced_menu_selector() {
    local -r prompt="$1" outvar="$2"
    shift 2
    local -a display_options=() return_values=()
    local parsing_display=true

    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            parsing_display=false
            shift
            continue
        fi
        if $parsing_display; then
            display_options+=("$1")
        else
            return_values+=("$1")
        fi
        shift
    done

    if (( ${#return_values[@]} == 0 )); then
        return_values=("${display_options[@]}")
    fi

    local count=${#display_options[@]}
    if (( count == 0 )); then
        echo "Error: No options provided" >&2
        return 1
    fi
    if (( ${#display_options[@]} != ${#return_values[@]} )); then
        echo "Error: Mismatched display and return value arrays" >&2
        return 1
    fi

    # Fix: Avoid potential pipeline issues with echo
    local cur=0 esc=$'\033'
    tput civis 2>/dev/null || true
    trap 'tput cnorm 2>/dev/null || true; stty echo 2>/dev/null || true' EXIT INT TERM
    stty -echo 2>/dev/null || true

    printf "%s\n" "$prompt"

    while true; do
        local index=0
        for o in "${display_options[@]}"; do
            if [[ $index == $cur ]]; then
                echo -e " >\e[1;32m $o \e[0m"
            else
                echo "   $o"
            fi
            (( ++index ))
        done

        read -s -n1 key || true
        if [[ $key == $esc ]]; then
            read -s -n2 -t 0.1 key 2>/dev/null || key=""
            case "$key" in
                "[A") 
                    (( cur-- )) || true
                    if (( cur < 0 )); then
                        cur=$((count - 1))
                    fi
                    ;;
                "[B") 
                    (( cur++ )) || true
                    if (( cur >= count )); then
                        cur=0
                    fi
                    ;;
            esac
        elif [[ $key == "" || $key == $'\n' || $key == $'\r' ]]; then
            break
        elif [[ $key == $'\003' || $key == "q" || $key == "Q" ]]; then
            tput cnorm 2>/dev/null || true
            stty echo 2>/dev/null || true
            trap - EXIT INT TERM
            echo -en "\e[${count}A"
            echo -e "\nSelection cancelled" >&2
            return 130
        fi

        echo -en "\e[${count}A"
    done

    tput cnorm 2>/dev/null || true
    stty echo 2>/dev/null || true
    trap - EXIT INT TERM

    echo -en "\e[${count}A"
    for (( i=0; i<count; i++ )); do echo -e "\e[K"; done
    echo -en "\e[${count}A"

    printf -v "$outvar" "${return_values[$cur]}"
    echo "Selected: ${display_options[$cur]} (value: ${return_values[$cur]})"

    return 0
}

simple_menu_selector() {
    local prompt="$1" outvar="$2"
    shift 2
    
    local -a display_options=() return_values=()
    local parsing_display=true
    
    while (( $# > 0 )); do
        if [[ "$1" == "--" ]]; then
            parsing_display=false
            shift
            continue
        fi
        
        if $parsing_display; then
            display_options+=("$1")
        else
            return_values+=("$1")
        fi
        shift
    done
    
    if (( ${#return_values[@]} == 0 )); then
        return_values=("${display_options[@]}")
    fi
    
    local cur=0 count=${#display_options[@]}
    
    while true; do
        clear
        printf "%s\n\n" "$prompt"
        
        for (( i=0; i<count; i++ )); do
            if (( i == cur )); then
                printf " %s>>%s %s %s<<%s\n" "$BOLD$GREEN" "$RESET" "${display_options[i]}" "$BOLD$GREEN" "$RESET"
            else
                printf "    %s\n" "${display_options[i]}"
            fi
        done
        
        printf "\n%sUse w/s or arrow keys to move, Enter to select, q to quit%s\n" "$CYAN" "$RESET"
        
        read -rsn1 key 2>/dev/null
        
        case $key in
            $'\033')
                read -rsn2 -t 0.1 key 2>/dev/null
                case $key in
                    '[A') (( cur-- )); (( cur < 0 )) && cur=$((count - 1)) ;;
                    '[B') (( cur++ )); (( cur >= count )) && cur=0 ;;
                esac
                ;;
            w|W) (( cur-- )); (( cur < 0 )) && cur=$((count - 1)) ;;
            s|S) (( cur++ )); (( cur >= count )) && cur=0 ;;
            ''|$'\n'|$'\r') break ;;
            q|Q|$'\003')
                clear
                echo "Selection cancelled"
                return 130
                ;;
        esac
    done
    
    clear
    printf -v "$outvar" "%s" "${return_values[$cur]}"
    printf "Selected: %s\n" "${display_options[$cur]}"
    return 0
}

numbered_menu_selector() {
    local prompt="$1" outvar="$2"
    shift 2
    
    local -a display_options=() return_values=()
    local parsing_display=true
    
    while (( $# > 0 )); do
        if [[ "$1" == "--" ]]; then
            parsing_display=false
            shift
            continue
        fi
        
        if $parsing_display; then
            display_options+=("$1")
        else
            return_values+=("$1")
        fi
        shift
    done
    
    if (( ${#return_values[@]} == 0 )); then
        return_values=("${display_options[@]}")
    fi
    
    local count=${#display_options[@]}
    
    printf "%s\n\n" "$prompt"
    for (( i=0; i<count; i++ )); do
        printf "%s%d.%s %s\n" "$BOLD" "$((i + 1))" "$RESET" "${display_options[i]}"
    done
    printf "\n"
    
    while true; do
        printf "Enter choice (1-%d) or q to quit: " "$count"
        read -r choice
        
        case $choice in
            q|Q)
                echo "Selection cancelled"
                return 130
                ;;
            ''|*[!0-9]*)
                printf "%sInvalid input. Please enter a number between 1 and %d.%s\n" "$YELLOW" "$count" "$RESET"
                continue
                ;;
            *)
                if (( choice >= 1 && choice <= count )); then
                    local selected_index=$((choice - 1))
                    printf -v "$outvar" "%s" "${return_values[$selected_index]}"
                    printf "Selected: %s\n" "${display_options[$selected_index]}"
                    return 0
                else
                    printf "%sInvalid choice. Please enter a number between 1 and %d.%s\n" "$YELLOW" "$count" "$RESET"
                fi
                ;;
        esac
    done
}

macos_menu_selector() {
    local prompt="$1" outvar="$2"
    shift 2
    
    local -a display_options=() return_values=()
    local parsing_display=true
    
    while (( $# > 0 )); do
        if [[ "$1" == "--" ]]; then
            parsing_display=false
            shift
            continue
        fi
        
        if $parsing_display; then
            display_options+=("$1")
        else
            return_values+=("$1")
        fi
        shift
    done
    
    if (( ${#return_values[@]} == 0 )); then
        return_values=("${display_options[@]}")
    fi
    
    local cur=0 count=${#display_options[@]}
    
    local GREEN='\033[0;32m'
    local CYAN='\033[0;36m'
    local BOLD='\033[1m'
    local RESET='\033[0m'
    local YELLOW='\033[0;33m'
    
    while true; do
        clear
        printf "%s\n\n" "$prompt"
        
        for (( i=0; i<count; i++ )); do
            if (( i == cur )); then
                printf " ${BOLD}${GREEN}>> %s <<${RESET}\n" "${display_options[i]}"
            else
                printf "   %s\n" "${display_options[i]}"
            fi
        done
        
        printf "\n${CYAN}Use ↑/↓ arrow keys or w/s to move, Enter to select, q to quit${RESET}\n"
        
        read -rsn1 key 2>/dev/null
        
        case $key in
            $'\033')
                read -rsn2 -t 0.1 key2 2>/dev/null
                case $key2 in
                    '[A') (( cur-- )); (( cur < 0 )) && cur=$((count - 1)) ;;
                    '[B') (( cur++ )); (( cur >= count )) && cur=0 ;;
                    '[C') ;;
                    '[D') ;;
                esac
                ;;
            A) (( cur-- )); (( cur < 0 )) && cur=$((count - 1)) ;;
            B) (( cur++ )); (( cur >= count )) && cur=0 ;;
            w|W) (( cur-- )); (( cur < 0 )) && cur=$((count - 1)) ;;
            s|S) (( cur++ )); (( cur >= count )) && cur=0 ;;
            ''|$'\n'|$'\r') break ;;
            q|Q|$'\003')
                clear
                echo "Selection cancelled"
                return 130
                ;;
        esac
    done
    
    clear
    printf -v "$outvar" "%s" "${return_values[$cur]}"
    printf "${GREEN}Selected: %s${RESET}\n" "${display_options[$cur]}"
    return 0
}

menu_selector() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)

    setup_colors "$capabilities"

    if [[ $capabilities == *"wsl"* ]]; then
        if [[ -n "${FORCE_SIMPLE_MENU:-}" ]]; then
            simple_menu_selector "$@"
        else
            advanced_menu_selector "$@"
        fi
    elif [[ $capabilities == *"macos"* ]] && [[ $capabilities == *"apple_terminal"* ]]; then
        macos_menu_selector "$@"
    elif [[ $capabilities == *"cursor_movement"* ]] && [[ $capabilities == *"read_timeout"* ]]; then
        advanced_menu_selector "$@"
    elif [[ $capabilities == *"interactive"* ]] && command -v clear >/dev/null 2>&1; then
        simple_menu_selector "$@"
    else
        numbered_menu_selector "$@"
    fi
}

print_header() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    setup_colors "$capabilities"
    
    printf "%s%s==========================================\n" "$BOLD" "$CYAN"
    printf "      %s       \n" "$1"
    printf "==========================================%s\n" "$RESET"
}

print_info() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    setup_colors "$capabilities"
    
    printf "%s%s[INFO]%s %s\n" "$BOLD" "$BLUE" "$RESET" "$1"
}

print_success() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    setup_colors "$capabilities"
    
    printf "%s%s[SUCCESS]%s %s\n" "$BOLD" "$GREEN" "$RESET" "$1"
}

print_warning() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    setup_colors "$capabilities"
    
    printf "%s%s[WARNING]%s %s\n" "$BOLD" "$YELLOW" "$RESET" "$1"
}

print_error() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    setup_colors "$capabilities"
    
    printf "%s%s[ERROR]%s %s\n" "$BOLD" "$RED" "$RESET" "$1"
}

print_guide() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    setup_colors "$capabilities"
    
    printf "%s%s%s%s\n" "$BOLD" "$BLUE" "$1" "$RESET"
}

print_prompt() {
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    setup_colors "$capabilities"
    
    printf "%s%s%s%s\n" "$BOLD" "$CYAN" "$1" "$RESET"
}

test_universal_menu() {
    echo "=== Universal Menu Selector Test ==="
    echo
    
    local capabilities
    capabilities=$(detect_terminal_capabilities)
    echo "Detected capabilities: $capabilities"
    echo
    
    local result
    menu_selector "Choose your favorite programming language:" result \
        "Python - Great for data science" \
        "JavaScript - Web development king" \
        "Bash - System administration" \
        "Go - Modern system programming" \
        "Rust - Memory safe performance" \
        -- \
        "python" "js" "bash" "golang" "rust"
    
    echo "You selected: $result"
    
    echo
    echo "Testing print functions:"
    print_header "Test Header"
    print_info "This is an info message"
    print_success "This is a success message"
    print_warning "This is a warning message"  
    print_error "This is an error message"
    print_guide "This is a guide message"
    print_prompt "This is a prompt message"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_universal_menu
fi