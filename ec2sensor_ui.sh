#!/bin/bash
# ec2sensor_ui.sh - Professional CLI UI Library
# Provides reusable components for terminal user interfaces
#
# Usage:
#   source ec2sensor_ui.sh
#   ui_header "My Application" "v1.0"
#   ui_info "Processing data..."
#   ui_success "Operation completed"

# ============================================
# Color Theme Support
# ============================================

# Available themes: dark, light, minimal
UI_THEME="${EC2SENSOR_THEME:-dark}"

# ============================================
# Color and Symbol Constants
# ============================================

# Base ANSI codes
_NC='\033[0m'           # No Color / Reset
_BOLD='\033[1m'
_DIM='\033[2m'

# Theme-specific color definitions
_init_theme_colors() {
    case "$UI_THEME" in
        light)
            # Light theme - darker colors for white backgrounds
            _RED='\033[0;31m'
            _GREEN='\033[0;32m'
            _YELLOW='\033[0;33m'      # Darker yellow for light bg
            _BLUE='\033[0;34m'
            _CYAN='\033[0;36m'
            _MAGENTA='\033[0;35m'
            _GRAY='\033[0;90m'
            _WHITE='\033[0;30m'       # Dark text on light bg
            _ACCENT='\033[0;34m'      # Blue accent
            _HEADER_BG='\033[44m'     # Blue background
            ;;
        minimal)
            # Minimal theme - no colors, just bold/dim
            _RED='\033[1m'
            _GREEN='\033[1m'
            _YELLOW='\033[1m'
            _BLUE='\033[1m'
            _CYAN='\033[1m'
            _MAGENTA='\033[1m'
            _GRAY='\033[2m'
            _WHITE='\033[1m'
            _ACCENT='\033[1m'
            _HEADER_BG=''
            ;;
        dark|*)
            # Dark theme (default) - bright colors for dark backgrounds
            _RED='\033[0;31m'
            _GREEN='\033[0;32m'
            _YELLOW='\033[1;33m'
            _BLUE='\033[0;34m'
            _CYAN='\033[0;34m'        # Using blue for better contrast
            _MAGENTA='\033[0;35m'
            _GRAY='\033[0;90m'
            _WHITE='\033[1;37m'
            _ACCENT='\033[0;34m'
            _HEADER_BG=''
            ;;
    esac
}

# Initialize theme colors
_init_theme_colors

# Export color variables (readonly after initialization)
NC="$_NC"
RED="$_RED"
GREEN="$_GREEN"
YELLOW="$_YELLOW"
BLUE="$_BLUE"
CYAN="$_CYAN"
MAGENTA="$_MAGENTA"
GRAY="$_GRAY"
WHITE="$_WHITE"
BOLD="$_BOLD"
DIM="$_DIM"
ACCENT="$_ACCENT"

# Function to switch theme at runtime
# Usage: ui_set_theme "light"
ui_set_theme() {
    UI_THEME="$1"
    _init_theme_colors
    NC="$_NC"
    RED="$_RED"
    GREEN="$_GREEN"
    YELLOW="$_YELLOW"
    BLUE="$_BLUE"
    CYAN="$_CYAN"
    MAGENTA="$_MAGENTA"
    GRAY="$_GRAY"
    WHITE="$_WHITE"
    ACCENT="$_ACCENT"
}

# Get current theme
# Usage: current=$(ui_get_theme)
ui_get_theme() {
    echo "$UI_THEME"
}

# Cycle to next theme
# Usage: ui_cycle_theme
ui_cycle_theme() {
    case "$UI_THEME" in
        dark) ui_set_theme "light" ;;
        light) ui_set_theme "minimal" ;;
        minimal) ui_set_theme "dark" ;;
    esac
    echo "$UI_THEME"
}

# Box-drawing characters (Unicode for professional look)
readonly BOX_TL="╭"        # Top-left corner (rounded)
readonly BOX_TR="╮"        # Top-right corner (rounded)
readonly BOX_BL="╰"        # Bottom-left corner (rounded)
readonly BOX_BR="╯"        # Bottom-right corner (rounded)
readonly BOX_H="─"         # Horizontal line
readonly BOX_V="│"         # Vertical line
readonly BOX_VR="├"        # Vertical-right junction
readonly BOX_VL="┤"        # Vertical-left junction
readonly BOX_HU="┴"        # Horizontal-up junction
readonly BOX_HD="┬"        # Horizontal-down junction
readonly BOX_CROSS="┼"     # Cross junction
readonly BOX_SIMPLE_H="─"  # Simple horizontal
readonly BOX_SIMPLE_V="│"  # Simple vertical

# Sharp corner variants (for tables)
readonly BOX_TL_SHARP="┌"  # Sharp top-left
readonly BOX_TR_SHARP="┐"  # Sharp top-right
readonly BOX_BL_SHARP="└"  # Sharp bottom-left
readonly BOX_BR_SHARP="┘"  # Sharp bottom-right

# Status Icons (Unicode for professional look)
readonly ICON_SUCCESS="✓"
readonly ICON_ERROR="✗"
readonly ICON_WARNING="⚠"
readonly ICON_INFO="ℹ"
readonly ICON_RUNNING="●"
readonly ICON_PENDING="○"
readonly ICON_STOPPED="◌"
readonly ICON_QUESTION="?"
readonly ICON_ARROW="›"
readonly ICON_CHECK="✓"
readonly ICON_CROSS="✗"
readonly ICON_BULLET="•"

# Spinner frames for animations (ASCII)
readonly SPINNER_FRAMES=("|" "/" "-" "\\" "|" "/" "-" "\\")

# Terminal width detection (default to 80 if can't detect)
UI_WIDTH="${COLUMNS:-80}"

# Check for color support
if [[ -n "$NO_COLOR" ]] || [[ ! -t 1 ]]; then
    UI_COLOR_ENABLED=false
    # Force minimal theme if colors disabled
    ui_set_theme "minimal"
else
    UI_COLOR_ENABLED=true
fi

# ============================================
# Helper Functions
# ============================================

# Apply color only if colors are enabled
_ui_color() {
    local color="$1"
    local text="$2"

    if [[ "$UI_COLOR_ENABLED" == true ]]; then
        echo -e "${color}${text}${NC}"
    else
        echo "$text"
    fi
}

# Get terminal width for dynamic formatting
_ui_get_width() {
    echo "${COLUMNS:-80}"
}

# Repeat a character N times
_ui_repeat() {
    local char="$1"
    local count="$2"
    printf "%${count}s" | tr ' ' "$char"
}

# Center text within a given width
_ui_center() {
    local text="$1"
    local width="${2:-$(_ui_get_width)}"
    local text_length="${#text}"
    local padding=$(( (width - text_length) / 2 ))

    printf "%${padding}s%s" "" "$text"
}

# Strip ANSI escape codes from a string to get visible length
_ui_strip_ansi() {
    local text="$1"
    # Remove ANSI escape sequences
    echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g'
}

# Get visible length of string (excluding ANSI codes)
_ui_visible_length() {
    local text="$1"
    local stripped=$(_ui_strip_ansi "$text")
    echo ${#stripped}
}

# Pad a string with ANSI codes to a fixed visible width
# Usage: _ui_pad_ansi "colored text" 10
_ui_pad_ansi() {
    local text="$1"
    local target_width="$2"
    local visible_len=$(_ui_visible_length "$text")
    local padding=$((target_width - visible_len))
    
    if [ $padding -gt 0 ]; then
        printf "%s%${padding}s" "$text" ""
    else
        printf "%s" "$text"
    fi
}

# ============================================
# Display Functions
# ============================================

# Display a professional header with simple line (legacy)
# Usage: ui_header "Title" ["Subtitle"]
ui_header() {
    local title="$1"
    local subtitle="${2:-}"

    # Use the new boxed header
    ui_header_box "$title" "$subtitle"
}

# Display a professional boxed header
# Usage: ui_header_box "Title" ["Subtitle"]
ui_header_box() {
    local title="$1"
    local subtitle="${2:-}"
    local width=60
    local inner_width=$((width - 2))
    
    # Combine title and subtitle
    local display_text="$title"
    if [[ -n "$subtitle" ]]; then
        display_text="$title  $subtitle"
    fi
    
    # Calculate padding for centering
    local text_len=${#display_text}
    local pad_total=$((inner_width - text_len))
    local pad_left=$((pad_total / 2))
    local pad_right=$((pad_total - pad_left))
    
    echo ""
    # Top border
    echo -e "\033[0;34m${BOX_TL}$(_ui_repeat "$BOX_H" $inner_width)${BOX_TR}\033[0m"
    # Title line - use CYAN for title text (visible on all backgrounds)
    printf "\033[0;34m${BOX_V}\033[0m%${pad_left}s\033[1;34m%s\033[0m%${pad_right}s\033[0;34m${BOX_V}\033[0m\n" "" "$display_text" ""
    # Bottom border
    echo -e "\033[0;34m${BOX_BL}$(_ui_repeat "$BOX_H" $inner_width)${BOX_BR}\033[0m"
    echo ""
}

# Display a horizontal divider
# Usage: ui_divider [character] [color]
ui_divider() {
    local char="${1:-$BOX_SIMPLE_H}"
    local color="${2:-$GRAY}"
    local width=$(_ui_get_width)

    _ui_color "$color" "$(_ui_repeat "$char" $width)"
}

# Display a section header (consistent style with menu headers)
# Usage: ui_section "Section Name"
ui_section() {
    local title="$1"

    echo ""
    echo -e "\033[1;34m  ${title}\033[0m"
    echo -e "\033[0;34m  ────────────────────────────────────────────────────\033[0m"
}

# Display a breadcrumb navigation (consistent style with section headers)
# Usage: ui_breadcrumb "Home" "Sensors" "Operations"
ui_breadcrumb() {
    local breadcrumb_path=("$@")
    local separator=" $ICON_ARROW "
    local output=""

    for i in "${!breadcrumb_path[@]}"; do
        if [[ $i -eq $((${#breadcrumb_path[@]} - 1)) ]]; then
            # Last item in bold
            output+="${breadcrumb_path[$i]}"
        else
            output+="${breadcrumb_path[$i]}"
            output+="$separator"
        fi
    done

    # Consistent style: title + underline
    echo -e "\033[1;34m  ${output}\033[0m"
    echo -e "\033[0;34m  ────────────────────────────────────────────────────\033[0m"
}

# ============================================
# Status & Feedback Functions
# ============================================

# Display success message with icon
# Usage: ui_success "Message" ["Details"]
ui_success() {
    local message="$1"
    local details="${2:-}"

    echo -e "  $(_ui_color "$GREEN" "${ICON_SUCCESS}") $(_ui_color "$GREEN" "$message")"

    if [[ -n "$details" ]]; then
        echo -e "$(_ui_color "$GRAY" "      $details")"
    fi
}

# Display error message with icon and optional suggestion
# Usage: ui_error "Message" ["Suggestion"]
ui_error() {
    local message="$1"
    local suggestion="${2:-}"

    echo -e "  $(_ui_color "$RED" "${ICON_ERROR}") $(_ui_color "$RED$BOLD" "$message")"

    if [[ -n "$suggestion" ]]; then
        echo -e "$(_ui_color "$YELLOW" "      ${ICON_INFO} Try: ${suggestion}")"
    fi
}

# Display warning message with icon
# Usage: ui_warning "Message" ["Details"]
ui_warning() {
    local message="$1"
    local details="${2:-}"

    echo -e "  $(_ui_color "$YELLOW" "${ICON_WARNING}") $(_ui_color "$YELLOW" "$message")"

    if [[ -n "$details" ]]; then
        echo -e "$(_ui_color "$GRAY" "      $details")"
    fi
}

# Display info message with icon
# Usage: ui_info "Message"
ui_info() {
    local message="$1"

    echo -e "  $(_ui_color "$CYAN" "${ICON_INFO}") $message"
}

# Get status icon for sensor status
# Usage: ui_status_icon "running"
# Returns: status text with icon
ui_status_icon() {
    local status="$1"

    case "$status" in
        running|active|enabled|success)
            _ui_color "$GREEN" "$ICON_RUNNING RUNNING"
            ;;
        starting|pending|provisioning)
            _ui_color "$YELLOW" "$ICON_PENDING PENDING"
            ;;
        stopped)
            _ui_color "$YELLOW" "$ICON_STOPPED STOPPED"
            ;;
        inactive|disabled|failed|error)
            _ui_color "$RED" "$ICON_ERROR ERROR"
            ;;
        *)
            echo "$ICON_QUESTION UNKNOWN"
            ;;
    esac
}

# Format health value with color (consolidated function)
# Usage: formatted=$(ui_format_health "45")
# Green: 0-59%, Yellow: 60-79%, Red: 80-100%
ui_format_health() {
    local value="$1"
    
    # Handle n/a or non-numeric values
    if [[ "$value" == "n/a" ]] || [[ -z "$value" ]] || [[ ! "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo -e "\033[0;90m-\033[0m"
        return
    fi
    
    # Convert to integer for comparison (remove decimal)
    local int_value=${value%.*}
    local display_value="${int_value}%"
    
    # Apply color based on threshold
    if [ "$int_value" -lt 60 ]; then
        echo -e "\033[0;32m${display_value}\033[0m"
    elif [ "$int_value" -lt 80 ]; then
        echo -e "\033[1;33m${display_value}\033[0m"
    else
        echo -e "\033[0;31m${display_value}\033[0m"
    fi
}

# Format health value with padding first, then color (for table alignment)
# Returns 6 chars visible width with color codes
ui_format_health_padded() {
    local value="$1"
    
    # Handle loading state - show animated dots
    if [[ "$value" == "..." ]]; then
        local padded=$(printf '%6s' '...')
        echo -e "\033[0;90m${padded}\033[0m"
        return
    fi
    
    # Handle n/a or non-numeric values - show "    -" (6 chars, right-aligned dash)
    if [[ "$value" == "n/a" ]] || [[ -z "$value" ]] || [[ ! "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        local padded=$(printf '%6s' '-')
        echo -e "\033[0;90m${padded}\033[0m"
        return
    fi
    
    # Convert to integer and format with % sign, right-aligned in 6 chars
    local int_value=${value%.*}
    local display_value=$(printf '%5d%%' "$int_value")
    
    # Apply color based on threshold
    if [ "$int_value" -lt 60 ]; then
        echo -e "\033[0;32m${display_value}\033[0m"
    elif [ "$int_value" -lt 80 ]; then
        echo -e "\033[1;33m${display_value}\033[0m"
    else
        echo -e "\033[0;31m${display_value}\033[0m"
    fi
}

# Alias for backwards compatibility
ui_health_value() {
    ui_format_health "$@"
}

# ============================================
# Progress Indicator Functions
# ============================================

# Display animated spinner (must be called in loop)
# Usage: ui_spinner "Loading..." &
#        SPINNER_PID=$!
#        # do work...
#        kill $SPINNER_PID
ui_spinner() {
    local message="${1:-Working}"
    local delay=0.1
    local frame=0

    # Hide cursor
    tput civis 2>/dev/null || true

    while true; do
        local spinner_char="${SPINNER_FRAMES[$frame]}"
        echo -ne "\r  $spinner_char $message..."
        frame=$(( (frame + 1) % ${#SPINNER_FRAMES[@]} ))
        sleep "$delay"
    done

    # Show cursor on exit
    trap 'tput cnorm 2>/dev/null || true' EXIT
}

# Display progress bar
# Usage: ui_progress_bar 50 100 "Processing"
ui_progress_bar() {
    local current="$1"
    local total="$2"
    local message="${3:-Progress}"
    local bar_width=40

    # Calculate percentage
    local percent=$(( (current * 100) / total ))
    local filled=$(( (current * bar_width) / total ))
    local empty=$((bar_width - filled))

    # Build bar with Unicode block characters
    local bar="$(_ui_color "$CYAN" "[")"
    bar+="$(_ui_color "$GREEN" "$(_ui_repeat "█" $filled)")"
    bar+="$(_ui_color "$GRAY" "$(_ui_repeat "░" $empty)")"
    bar+="$(_ui_color "$CYAN" "]")"

    # Display with percentage
    echo -ne "\r  $bar $(_ui_color "$BOLD" "${percent}%") ${message}    "

    # Newline if complete
    if [[ $current -ge $total ]]; then
        echo ""
    fi
}

# Display simple waiting dots animation
# Usage: ui_waiting_dots "Loading" 5
ui_waiting_dots() {
    local message="$1"
    local duration="${2:-3}"
    local dots=""

    echo -ne "  $message"

    for ((i=0; i<duration; i++)); do
        dots+="."
        echo -ne "\r  $message$dots   "
        sleep 0.5
    done

    echo "" # Newline
}

# ============================================
# Menu System Functions
# ============================================

# Display menu header (kubectl/docker style - no box borders)
# Usage: ui_menu_header "Main Menu"
ui_menu_header() {
    local title="$1"
    echo ""
    echo -e "\033[1;34m  ${title}\033[0m"
    echo -e "\033[0;34m  ────────────────────────────────────────────────────\033[0m"
}

# Display formatted menu item (kubectl/docker style - clean and simple)
# Usage: ui_menu_item 1 "" "Connect" ["Description"] [color]
ui_menu_item() {
    local number="$1"
    local icon="${2:-}"  # Ignored, kept for compatibility
    local label="$3"
    local description="${4:-}"
    
    # Simple clean format: [n] Label
    echo -e "  \033[1;34m[$number]\033[0m  $label"

    if [[ -n "$description" ]]; then
        echo -e "       \033[0;90m$description\033[0m"
    fi
}

# Display menu footer with hints (kubectl/docker style)
# Usage: ui_menu_footer "Select option [1-5]"
ui_menu_footer() {
    local hint="$1"
    echo ""
    echo -e "\033[0;90m  $hint\033[0m"
}

# ============================================
# Input Validation Functions
# ============================================

# Read and validate numeric choice
# Usage: ui_read_choice "Select option" 1 5
# Returns: validated choice via echo
ui_read_choice() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local choice

    while true; do
        echo -ne "\n  ${prompt} [${min}-${max}]: > " >&2
        read -r choice

        # Validate numeric and in range
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$min" ] && [ "$choice" -le "$max" ]; then
            echo "$choice"
            return 0
        else
            echo "  [ERROR] Invalid choice. Please enter a number between $min and $max." >&2
        fi
    done
}

# Read choice with keyboard shortcuts
# Usage: ui_read_choice_with_shortcuts "Select" 1 5 "main"
# Returns: Choice number OR shortcut action (e.g., "REFRESH", "QUIT", "NEW", "HELP")
ui_read_choice_with_shortcuts() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local context="${4:-main}"
    local choice
    local choice_lower

    while true; do
        echo -ne "\n  ${prompt} [${min}-${max}]: > " >&2
        read -r choice || {
            # Handle Ctrl+C or read error
            echo "" >&2
            echo "QUIT"
            return 0
        }

        # Handle empty input (just Enter pressed) - show hint
        if [ -z "$choice" ]; then
            echo "  $(_ui_color "$GRAY" "Hint: Enter a number [${min}-${max}] or press [?] for help")" >&2
            continue
        fi

        # Convert to lowercase (bash 3.x compatible)
        choice_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

        # Check for keyboard shortcuts (case-insensitive)
        case "$choice_lower" in
            r) echo "REFRESH"; return 0 ;;
            q) echo "QUIT"; return 0 ;;
            n) echo "NEW"; return 0 ;;
            c) echo "CONNECT"; return 0 ;;
            d) echo "DELETE"; return 0 ;;
            f) echo "FEATURES"; return 0 ;;
            u) echo "UPGRADE"; return 0 ;;
            b) echo "BACK"; return 0 ;;
            s) echo "START"; return 0 ;;
            x) echo "STOP"; return 0 ;;
            m) echo "MULTISELECT"; return 0 ;;
            t) echo "THEME"; return 0 ;;
            h) echo "HEALTH"; return 0 ;;
            a) echo "ALL"; return 0 ;;
            '?'|help) echo "HELP"; return 0 ;;
        esac

        # Validate numeric and in range
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$min" ] && [ "$choice" -le "$max" ]; then
            echo "$choice"
            return 0
        else
            echo "  [ERROR] Invalid choice. Enter a number [$min-$max] or press [?] for help." >&2
        fi
    done
}

# Read yes/no confirmation
# Usage: if ui_read_confirm "Delete sensor?"; then ... fi
ui_read_confirm() {
    local prompt="$1"
    local details="${2:-}"
    local response

    echo "" >&2
    if [[ -n "$details" ]]; then
        echo -e "$(_ui_color "$YELLOW" "  ${ICON_WARNING} $details")" >&2
    fi

    echo -ne "\n  ${prompt} (y/N): > " >&2
    read -r response

    # Convert to lowercase (bash 3.x compatible)
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    [[ "$response" =~ ^y(es)?$ ]]
}

# Read text input with optional validation
# Usage: result=$(ui_read_text "Enter IP address" "^[0-9.]+$")
ui_read_text() {
    local prompt="$1"
    local validation_pattern="${2:-}"
    local input

    while true; do
        echo -ne "\n  ${prompt}: > " >&2
        read -r input

        # If no validation pattern, accept any non-empty input
        if [[ -z "$validation_pattern" ]]; then
            if [[ -n "$input" ]]; then
                echo "$input"
                return 0
            else
                echo "  [ERROR] Input cannot be empty" >&2
            fi
        # Validate against pattern
        elif [[ "$input" =~ $validation_pattern ]]; then
            echo "$input"
            return 0
        else
            echo "  [ERROR] Invalid input format" >&2
        fi
    done
}

# Read password (silent input)
# Usage: password=$(ui_read_password "Enter password")
ui_read_password() {
    local prompt="$1"
    local password

    echo -ne "\n  ${prompt}: > " >&2
    read -rs password
    echo "" >&2 # Newline after silent input

    echo "$password"
}

# ============================================
# Table and List Functions
# ============================================

# Display table header with columns
# Usage: ui_table_header "ID" "NAME" "STATUS" "IP"
ui_table_header() {
    local columns=("$@")

    echo ""
    printf "  %-6s%-24s%-20s%-15s\n" "${columns[0]}" "${columns[1]}" "${columns[2]}" "${columns[3]}"
    ui_divider "$BOX_SIMPLE_H" "$GRAY"
}

# Display table row
# Usage: ui_table_row "1" "sensor-123" "running" "10.50.88.53"
ui_table_row() {
    # Print columns with proper spacing - status field has extra padding to account for color codes
    printf "  %-6s%-24s%s            %s\n" "$1" "$2" "$3" "$4"
}

# Display enhanced table header with resource metrics (kubectl/docker style - no vertical borders)
# This approach is more reliable and looks professional like kubectl, docker ps, htop
# Usage: ui_table_header_enhanced
ui_table_header_enhanced() {
    # Calculate table width: 2(indent) + 4 + 1 + 10 + 1 + 12 + 1 + 6 + 1 + 6 + 1 + 6 + 1 + 5 + 2 + 15 = 69
    local line="────────────────────────────────────────────────────────────────────"
    
    # Top separator line
    echo -e "\033[0;34m  ${line}\033[0m"
    
    # Header row with fixed widths using printf
    printf "  \033[1m%-4s %-10s %-12s %6s %6s %6s %5s  %-15s\033[0m\n" \
           "ID" "SENSOR" "STATUS" "CPU%" "MEM%" "DISK%" "PODS" "IP"
    
    # Separator line
    echo -e "\033[0;34m  ${line}\033[0m"
}

# Display enhanced table row with resource metrics (kubectl/docker style)
# Usage: ui_table_row_enhanced "1" "8249" "● RUNNING" "15.2" "42" "67" "8" "10.50.88.154"
ui_table_row_enhanced() {
    local id="$1"
    local sensor="$2"
    local status="$3"
    local cpu="$4"
    local mem="$5"
    local disk="$6"
    local pods="$7"
    local ip="$8"
    
    # Format health values - pad first, then color
    local cpu_fmt=$(ui_format_health_padded "$cpu")
    local mem_fmt=$(ui_format_health_padded "$mem")
    local disk_fmt=$(ui_format_health_padded "$disk")
    
    # Format pods
    local pods_fmt
    if [[ "$pods" == "n/a" ]] || [[ -z "$pods" ]]; then
        pods_fmt="\033[0;90m$(printf '%5s' '-')\033[0m"
    else
        pods_fmt=$(printf '%5s' "$pods")
    fi
    
    # Format status - strip colors, pad to 12 chars, then re-apply color
    # This preserves the ● symbol while ensuring proper width
    local status_plain
    status_plain=$(echo -e "$status" | sed 's/\x1b\[[0-9;]*m//g')
    local status_padded=$(printf '%-12s' "$status_plain")
    
    # Re-apply color to the padded status (keeps ● symbol)
    local status_colored
    case "$status_plain" in
        *RUNNING*) status_colored="\033[0;32m${status_padded}\033[0m" ;;
        *PENDING*) status_colored="\033[1;33m${status_padded}\033[0m" ;;
        *ERROR*)   status_colored="\033[0;31m${status_padded}\033[0m" ;;
        *STOPPED*) status_colored="\033[1;33m${status_padded}\033[0m" ;;
        *)         status_colored="$status_padded" ;;
    esac
    
    # Print row using printf with %b for colored fields
    printf "  %-4s %-10s %b %b %b %b %b  %-15s\n" \
           "$id" "$sensor" "$status_colored" "$cpu_fmt" "$mem_fmt" "$disk_fmt" "$pods_fmt" "$ip"
}

# Display table footer (bottom border)
# Usage: ui_table_footer_enhanced
ui_table_footer_enhanced() {
    local line="────────────────────────────────────────────────────────────────────"
    echo -e "\033[0;34m  ${line}\033[0m"
}

# Display list item (bullet or numbered)
# Usage: ui_list_item "Item text" ["prefix"]
ui_list_item() {
    local text="$1"
    local prefix="${2:--}"

    echo "  $prefix $text"
}

# ============================================
# Special Display Functions
# ============================================

# Display key-value pair
# Usage: ui_key_value "Status" "running"
ui_key_value() {
    local key="$1"
    local value="$2"
    local key_width=18

    printf "  $(_ui_color "$GRAY" "${ICON_BULLET}") %-${key_width}s %s\n" "$(_ui_color "$CYAN" "${key}")" "$value"
}

# Display a box with content
# Usage: ui_box "Title" "Line 1" "Line 2" "Line 3"
ui_box() {
    local title="$1"
    shift
    local lines=("$@")
    local width=$(_ui_get_width)
    local inner_width=$((width - 4))

    # Top border with title
    echo ""
    echo "${BOX_TL}${BOX_H}${BOX_H} ${title} $(_ui_repeat "$BOX_H" $((inner_width - ${#title} - 3)))${BOX_TR}"

    # Content lines
    for line in "${lines[@]}"; do
        printf "${BOX_V} %-${inner_width}s ${BOX_V}\n" "$line"
    done

    # Bottom border
    echo "${BOX_BL}$(_ui_repeat "$BOX_H" $inner_width)${BOX_BR}"
    echo ""
}

# Display a summary dashboard
# Usage: ui_dashboard "Sensor Status" "key1=value1" "key2=value2" ...
ui_dashboard() {
    local title="$1"
    shift
    local pairs=("$@")

    ui_box "$title"

    for pair in "${pairs[@]}"; do
        local key="${pair%%=*}"
        local value="${pair#*=}"
        ui_key_value "$key" "$value"
    done

    echo ""
}

# ============================================
# Status Bar Functions
# ============================================

# Display status bar with session stats
# Usage: ui_status_bar "3" "0" "300" "5"
# Args: running_count, error_count, session_duration_seconds, last_refresh_age_seconds
ui_status_bar() {
    local running="$1"
    local errors="$2"
    local session_duration="$3"
    local last_refresh_age="$4"

    local duration_str=$(ui_format_duration "$session_duration")
    local refresh_str=""

    # Color code refresh age
    if [ "$last_refresh_age" -lt 10 ]; then
        refresh_str="$(_ui_color "$GREEN" "[Last Updated: ${last_refresh_age}s ago]")"
    elif [ "$last_refresh_age" -lt 60 ]; then
        refresh_str="$(_ui_color "$YELLOW" "[Last Updated: ${last_refresh_age}s ago]")"
    elif [ "$last_refresh_age" -gt 999 ]; then
        refresh_str="[Never Updated]"
    else
        refresh_str="$(_ui_color "$RED" "[Last Updated: ${last_refresh_age}s ago]")"
    fi

    # Add 2-space indent to align with other content
    echo -n "  $refresh_str "

    # Running sensors
    if [ "$running" -gt 0 ]; then
        echo -n "$(_ui_color "$GREEN" "[$running Running]") "
    else
        echo -n "[0 Running] "
    fi

    # Errors
    if [ "$errors" -gt 0 ]; then
        echo -n "$(_ui_color "$RED" "[$errors Errors]") "
    else
        echo -n "[0 Errors] "
    fi

    # Session duration
    echo "[Session: $duration_str]"
}

# ============================================
# Time Utility Functions
# ============================================

# Format seconds into human-readable duration
# Usage: ui_format_duration 7265
# Output: "2h 1m"
ui_format_duration() {
    local total_seconds="$1"

    if [ "$total_seconds" -lt 60 ]; then
        echo "${total_seconds}s"
    elif [ "$total_seconds" -lt 3600 ]; then
        local minutes=$((total_seconds / 60))
        local seconds=$((total_seconds % 60))
        echo "${minutes}m ${seconds}s"
    elif [ "$total_seconds" -lt 86400 ]; then
        local hours=$((total_seconds / 3600))
        local minutes=$(((total_seconds % 3600) / 60))
        echo "${hours}h ${minutes}m"
    else
        local days=$((total_seconds / 86400))
        local hours=$(((total_seconds % 86400) / 3600))
        echo "${days}d ${hours}h"
    fi
}

# Format timestamp to relative time
# Usage: ui_format_age 1704729791
# Output: "3d 4h ago"
ui_format_age() {
    local timestamp="$1"
    local now=$(date +%s)
    local diff=$((now - timestamp))

    if [ "$diff" -lt 60 ]; then
        echo "${diff}s ago"
    elif [ "$diff" -lt 3600 ]; then
        local minutes=$((diff / 60))
        echo "${minutes}m ago"
    elif [ "$diff" -lt 86400 ]; then
        local hours=$((diff / 3600))
        local minutes=$(((diff % 3600) / 60))
        echo "${hours}h ${minutes}m ago"
    else
        local days=$((diff / 86400))
        local hours=$(((diff % 86400) / 3600))
        echo "${days}d ${hours}h ago"
    fi
}

# Calculate uptime from timestamp
# Usage: ui_calc_uptime "$start_time"
# Output: "2h 15m"
ui_calc_uptime() {
    local start_time="$1"
    local now=$(date +%s)
    local uptime=$((now - start_time))

    ui_format_duration "$uptime"
}

# Format timestamp to human date
# Usage: ui_format_datetime 1704729791
# Output: "2025-01-05 14:23:11"
ui_format_datetime() {
    local timestamp="$1"

    if command -v date &> /dev/null; then
        # macOS and Linux compatible
        date -r "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || \
        date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || \
        echo "unknown"
    else
        echo "unknown"
    fi
}

# ============================================
# Utility Functions
# ============================================

# Clear screen and show header (for full-screen menus)
# Usage: ui_clear_screen "EC2 Sensor Manager"
ui_clear_screen() {
    local title="${1:-}"

    clear

    if [[ -n "$title" ]]; then
        ui_header "$title"
    fi
}

# Display elapsed time in human-readable format
# Usage: ui_elapsed_time 125
# Output: "2m 5s"
ui_elapsed_time() {
    local seconds="$1"
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))

    if [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${remaining_seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Display file size in human-readable format
# Usage: ui_file_size 1048576
# Output: "1.0 MB"
ui_file_size() {
    local bytes="$1"

    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}") KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}") GB"
    fi
}

# ============================================
# Keyboard Shortcuts
# ============================================

# Display keyboard shortcuts footer (consistent style with other sections)
# Usage: ui_shortcuts_footer "main"  # Context: main, operations, traffic
ui_shortcuts_footer() {
    local context="${1:-main}"
    local g="$GRAY"

    echo ""
    echo -e "\033[1;34m  Shortcuts\033[0m"
    echo -e "\033[0;34m  ────────────────────────────────────────────────────\033[0m"
    echo -n "  "

    case "$context" in
        main)
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "r")$(_ui_color "$g" "]efresh")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "n")$(_ui_color "$g" "]ew")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "m")$(_ui_color "$g" "]ulti-select")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "t")$(_ui_color "$g" "]heme")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "q")$(_ui_color "$g" "]uit")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "?")$(_ui_color "$g" "]help")"
            ;;
        operations)
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "c")$(_ui_color "$g" "]onnect")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "f")$(_ui_color "$g" "]eatures")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "u")$(_ui_color "$g" "]pgrade")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "d")$(_ui_color "$g" "]elete")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "h")$(_ui_color "$g" "]ealth")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "b")$(_ui_color "$g" "]ack")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "?")$(_ui_color "$g" "]help")"
            ;;
        traffic)
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "s")$(_ui_color "$g" "]tart")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "x")$(_ui_color "$g" "] stop")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "b")$(_ui_color "$g" "]ack")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "?")$(_ui_color "$g" "]help")"
            ;;
        bulk)
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "a")$(_ui_color "$g" "]ll")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "n")$(_ui_color "$g" "]one")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "d")$(_ui_color "$g" "]elete selected")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "f")$(_ui_color "$g" "]eatures")"
            echo -n "  "
            echo -n "$(_ui_color "$g" "[")$(_ui_color "$CYAN" "b")$(_ui_color "$g" "]ack")"
            ;;
    esac
    echo ""
}

# Display help screen
# Usage: ui_show_help "main"  # Context: main, operations, traffic
ui_show_help() {
    local context="${1:-main}"

    clear
    ui_header "KEYBOARD SHORTCUTS" "Help"

    ui_section "Navigation"
    echo "  $(_ui_color "$CYAN" "1-9")     Select item by number"
    echo "  $(_ui_color "$CYAN" "Enter")   Confirm selection"
    echo "  $(_ui_color "$CYAN" "?")       Show this help screen"
    echo ""

    case "$context" in
        main)
            ui_section "Main Menu Shortcuts"
            echo "  $(_ui_color "$CYAN" "r")       Refresh sensor list"
            echo "  $(_ui_color "$CYAN" "n")       Deploy new sensor"
            echo "  $(_ui_color "$CYAN" "m")       Multi-select mode (bulk operations)"
            echo "  $(_ui_color "$CYAN" "t")       Cycle color theme (dark/light/minimal)"
            echo "  $(_ui_color "$CYAN" "q")       Quit application"
            ;;
        operations)
            ui_section "Sensor Operations Shortcuts"
            echo "  $(_ui_color "$CYAN" "c")       Connect via SSH"
            echo "  $(_ui_color "$CYAN" "f")       Enable features (HTTP, YARA, etc.)"
            echo "  $(_ui_color "$CYAN" "u")       Upgrade sensor"
            echo "  $(_ui_color "$CYAN" "d")       Delete sensor"
            echo "  $(_ui_color "$CYAN" "h")       Health dashboard (detailed view)"
            echo "  $(_ui_color "$CYAN" "b")       Back to sensor list"
            ;;
        traffic)
            ui_section "Traffic Generator Shortcuts"
            echo "  $(_ui_color "$CYAN" "s")       Start traffic generation"
            echo "  $(_ui_color "$CYAN" "x")       Stop traffic generation"
            echo "  $(_ui_color "$CYAN" "b")       Back to operations menu"
            ;;
        bulk)
            ui_section "Bulk Operations Shortcuts"
            echo "  $(_ui_color "$CYAN" "a")       Select all sensors"
            echo "  $(_ui_color "$CYAN" "n")       Deselect all sensors"
            echo "  $(_ui_color "$CYAN" "1-9")     Toggle selection for sensor"
            echo "  $(_ui_color "$CYAN" "d")       Delete selected sensors"
            echo "  $(_ui_color "$CYAN" "f")       Enable features on selected"
            echo "  $(_ui_color "$CYAN" "b")       Back to main menu"
            ;;
    esac

    echo ""
    ui_section "Tips"
    echo "  • Shortcuts are case-insensitive (r = R)"
    echo "  • Press Enter on empty input to see hint"
    echo "  • Use Ctrl+C to exit at any time"
    echo "  • Set EC2SENSOR_THEME=light for light terminals"
    echo ""

    ui_section "Environment Variables"
    echo "  $(_ui_color "$GRAY" "SSH_USERNAME")         SSH user for sensor connections"
    echo "  $(_ui_color "$GRAY" "SSH_PASSWORD")         SSH password (or use SSH keys)"
    echo "  $(_ui_color "$GRAY" "EC2_SENSOR_BASE_URL")  API endpoint URL"
    echo "  $(_ui_color "$GRAY" "EC2_SENSOR_API_KEY")   API authentication key"
    echo "  $(_ui_color "$GRAY" "EC2SENSOR_THEME")      Color theme (dark/light/minimal)"
    echo ""

    echo "  Press any key to return..."
    read -n 1 -r
}

# ============================================
# Sensor Health Dashboard
# ============================================

# Display detailed sensor health dashboard
# Usage: ui_health_dashboard "sensor-name" "ip" "status" "cpu" "mem" "disk" "pods" "uptime" "services_json"
ui_health_dashboard() {
    local sensor_name="$1"
    local ip="$2"
    local status="$3"
    local cpu="$4"
    local mem="$5"
    local disk="$6"
    local pods="$7"
    local uptime="${8:-unknown}"
    local services="${9:-}"
    
    ui_header "SENSOR HEALTH DASHBOARD" "${sensor_name##*-}"
    
    # Overview section
    ui_section "Overview"
    ui_key_value "Sensor ID" "${sensor_name##*-}"
    ui_key_value "IP Address" "$ip"
    ui_key_value "Status" "$(ui_status_icon "$status")"
    ui_key_value "Uptime" "$uptime"
    
    # Resource usage section with visual bars
    echo ""
    ui_section "Resource Usage"
    
    # CPU bar
    local cpu_val=${cpu%.*}
    [ "$cpu_val" = "n/a" ] && cpu_val=0
    echo -n "  CPU:    "
    _ui_resource_bar "$cpu_val" 100
    echo " $(ui_format_health "$cpu")"
    
    # Memory bar
    local mem_val=${mem%.*}
    [ "$mem_val" = "n/a" ] && mem_val=0
    echo -n "  Memory: "
    _ui_resource_bar "$mem_val" 100
    echo " $(ui_format_health "$mem")"
    
    # Disk bar
    local disk_val=${disk%.*}
    [ "$disk_val" = "n/a" ] && disk_val=0
    echo -n "  Disk:   "
    _ui_resource_bar "$disk_val" 100
    echo " $(ui_format_health "$disk")"
    
    # Services section
    echo ""
    ui_section "Services"
    if [ -n "$services" ] && [ "$services" != "{}" ]; then
        echo "$services" | while IFS='|' read -r svc_name svc_status; do
            [ -z "$svc_name" ] && continue
            local icon
            case "$svc_status" in
                Ok|running|active) icon="$(_ui_color "$GREEN" "●")" ;;
                *) icon="$(_ui_color "$RED" "●")" ;;
            esac
            echo "  $icon $svc_name: $svc_status"
        done
    else
        ui_key_value "Running Services" "$pods"
    fi
    
    # Network section (placeholder for future)
    echo ""
    ui_section "Quick Actions"
    echo "  $(_ui_color "$CYAN" "[1]") SSH Connect    $(_ui_color "$CYAN" "[2]") View Logs    $(_ui_color "$CYAN" "[3]") Restart Services"
    echo "  $(_ui_color "$CYAN" "[b]") Back to Operations"
}

# Helper: Draw a resource usage bar
# Usage: _ui_resource_bar 75 100
_ui_resource_bar() {
    local value="$1"
    local max="$2"
    local width=20
    
    # Handle non-numeric
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        value=0
    fi
    
    local filled=$((value * width / max))
    [ $filled -gt $width ] && filled=$width
    local empty=$((width - filled))
    
    # Color based on value
    local color
    if [ "$value" -lt 60 ]; then
        color="$GREEN"
    elif [ "$value" -lt 80 ]; then
        color="$YELLOW"
    else
        color="$RED"
    fi
    
    echo -n "["
    echo -ne "$color"
    printf '%*s' "$filled" '' | tr ' ' '█'
    echo -ne "$NC"
    printf '%*s' "$empty" '' | tr ' ' '░'
    echo -n "]"
}

# Display offline mode indicator with reason and cache age
# Usage: ui_offline_indicator "reason" "cache_age_seconds"
# Example: ui_offline_indicator "Network unreachable" "120"
ui_offline_indicator() {
    local reason="${1:-API unreachable}"
    local cache_age="${2:-}"
    
    # Format cache age as human-readable
    local age_str=""
    if [ -n "$cache_age" ] && [ "$cache_age" != "999999" ]; then
        if [ "$cache_age" -lt 60 ]; then
            age_str="cached ${cache_age}s ago"
        elif [ "$cache_age" -lt 3600 ]; then
            local mins=$((cache_age / 60))
            age_str="cached ${mins}m ago"
        elif [ "$cache_age" -lt 86400 ]; then
            local hours=$((cache_age / 3600))
            local mins=$(((cache_age % 3600) / 60))
            age_str="cached ${hours}h ${mins}m ago"
        else
            local days=$((cache_age / 86400))
            age_str="cached ${days}d ago"
        fi
    else
        age_str="no cached data"
    fi
    
    # Display with reason and age
    echo -e "  $(_ui_color "$YELLOW" "⚠ OFFLINE MODE") - $(_ui_color "$RED" "$reason") $(_ui_color "$GRAY" "($age_str)")"
}

# Display API status indicator
# Usage: ui_api_status true "Connected"
ui_api_status() {
    local online="$1"
    local message="${2:-}"
    
    if [ "$online" = true ]; then
        echo -e "  $(_ui_color "$GREEN" "● API Online") $(_ui_color "$GRAY" "$message")"
    else
        echo -e "  $(_ui_color "$RED" "● API Offline") $(_ui_color "$YELLOW" "$message")"
    fi
}

# Display bulk selection table row
# Usage: ui_table_row_bulk_select "1" "sensor" "status" "cpu" "mem" "disk" "pods" "ip" true/false
ui_table_row_bulk_select() {
    local id="$1"
    local sensor="$2"
    local status="$3"
    local cpu="$4"
    local mem="$5"
    local disk="$6"
    local pods="$7"
    local ip="$8"
    local selected="${9:-false}"
    
    # Selection indicator
    local sel_indicator
    if [ "$selected" = true ]; then
        sel_indicator="$(_ui_color "$GREEN" "[✓]")"
    else
        sel_indicator="$(_ui_color "$GRAY" "[ ]")"
    fi
    
    # Format health values
    local cpu_fmt=$(ui_format_health_padded "$cpu")
    local mem_fmt=$(ui_format_health_padded "$mem")
    local disk_fmt=$(ui_format_health_padded "$disk")
    
    # Format pods
    local pods_fmt
    if [[ "$pods" == "n/a" ]] || [[ -z "$pods" ]]; then
        pods_fmt="\033[0;90m$(printf '%5s' '-')\033[0m"
    else
        pods_fmt=$(printf '%5s' "$pods")
    fi
    
    # Format status
    local status_plain
    status_plain=$(echo -e "$status" | sed 's/\x1b\[[0-9;]*m//g')
    local status_padded=$(printf '%-12s' "$status_plain")
    local status_colored
    case "$status_plain" in
        *RUNNING*) status_colored="\033[0;32m${status_padded}\033[0m" ;;
        *PENDING*) status_colored="\033[1;33m${status_padded}\033[0m" ;;
        *ERROR*)   status_colored="\033[0;31m${status_padded}\033[0m" ;;
        *STOPPED*) status_colored="\033[1;33m${status_padded}\033[0m" ;;
        *)         status_colored="$status_padded" ;;
    esac
    
    # Print row with selection checkbox
    printf "  %b %-3s %-10s %b %b %b %b %b  %-15s\n" \
           "$sel_indicator" "$id" "$sensor" "$status_colored" "$cpu_fmt" "$mem_fmt" "$disk_fmt" "$pods_fmt" "$ip"
}

# Display bulk selection table header
# Usage: ui_table_header_bulk_select
ui_table_header_bulk_select() {
    local line="─────────────────────────────────────────────────────────────────────────"
    
    echo -e "\033[0;34m  ${line}\033[0m"
    printf "  \033[1m%-4s %-3s %-10s %-12s %6s %6s %6s %5s  %-15s\033[0m\n" \
           "SEL" "ID" "SENSOR" "STATUS" "CPU%" "MEM%" "DISK%" "PODS" "IP"
    echo -e "\033[0;34m  ${line}\033[0m"
}

# Display loading placeholder for lazy metrics
# Usage: ui_loading_placeholder "Loading..."
ui_loading_placeholder() {
    local message="${1:-Loading...}"
    echo -e "\033[0;90m${message}\033[0m"
}

# ============================================
# Testing and Examples
# ============================================

# Test function to demonstrate all UI components
# Usage: ui_test
ui_test() {
    ui_clear_screen "UI Library Test"

    ui_breadcrumb "Home" "Testing" "UI Components"

    ui_section "Display Functions"
    ui_info "This is an info message"
    ui_success "This is a success message"
    ui_warning "This is a warning message"
    ui_error "This is an error message" "Try fixing the issue"

    echo ""
    ui_section "Table Example"
    ui_table_header "ID" "NAME" "STATUS" "VALUE"
    ui_table_row "1" "Test 1" "$(ui_status_icon "running") Running" "100"
    ui_table_row "2" "Test 2" "$(ui_status_icon "pending") Pending" "50"
    ui_table_row "3" "Test 3" "$(ui_status_icon "error") Error" "0"

    echo ""
    ui_section "Menu Example"
    ui_menu_header "Operations"
    ui_menu_item 1 "🔌" "Connect" "SSH to sensor"
    ui_menu_item 2 "⚙️" "Configure" "Change settings"
    ui_menu_item 3 "🗑️" "Delete" "Remove sensor" "$RED"
    ui_menu_footer "Select option [1-3]"

    echo ""
    ui_section "Progress Example"
    for i in 0 20 40 60 80 100; do
        ui_progress_bar "$i" 100 "Processing"
        sleep 0.3
    done

    echo ""
    ui_section "Status Icons"
    echo "  Running: $(ui_status_icon "running")"
    echo "  Pending: $(ui_status_icon "pending")"
    echo "  Error: $(ui_status_icon "error")"

    echo ""
}

# ============================================
# Initialization
# ============================================

# Check if terminal supports UTF-8 (for box characters)
if [[ "$LANG" != *UTF-8* ]] && [[ "$LC_ALL" != *UTF-8* ]]; then
    ui_warning "Terminal may not support UTF-8. Some characters may not display correctly."
fi

# Export functions for use in subshells (if needed)
# This allows functions to be used in command substitution
export -f ui_header ui_divider ui_section ui_breadcrumb 2>/dev/null || true
export -f ui_success ui_error ui_warning ui_info ui_status_icon 2>/dev/null || true
export -f ui_menu_header ui_menu_item ui_menu_footer 2>/dev/null || true
export -f ui_table_header ui_table_row ui_list_item 2>/dev/null || true
export -f ui_table_header_enhanced ui_table_row_enhanced ui_table_footer_enhanced 2>/dev/null || true
export -f ui_format_health ui_health_value ui_header_box ui_set_theme ui_get_theme ui_cycle_theme 2>/dev/null || true
export -f ui_progress_bar ui_spinner ui_waiting_dots 2>/dev/null || true
export -f ui_read_choice ui_read_confirm ui_read_text ui_read_password 2>/dev/null || true

# Success message when library is sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Only show if not running as main script
    : # Silent load
else
    # If run directly, show test
    ui_test
fi
