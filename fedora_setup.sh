#!/bin/bash
set -e

if ! command -v dnf &>/dev/null; then
    echo ""
    echo "Warning: 'dnf' not found! This script may fail or behave incorrectly."
    echo "Continuing anyway... Please proceed at your own risk."
    sleep 5
fi


PACKAGE_LIST_FILE="$(pwd)/pkglist.txt"
# Get the directory of the script
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PACKAGE_LIST_FILE="$SCRIPT_DIR/pkglist.txt"
USER_SHELL=$(getent passwd "$USER" | cut -d: -f7)

# Resolve working directory to original script location
script_dir="$(dirname "$(readlink -f "$0")")"
cd "$script_dir" || { echo "Failed to enter script directory"; exit 1; }


# ----- Fedora Functions -----

update_system() {
    echo "Updating the system..."
    dnf upgrade -y
    echo "System update completed."
    sleep 3
    show_menu
}

install_packages() {
    echo "Enter the package(s) you want to install (space-separated), or press 0 to return:"
    read -rp "Packages: " packages
    if [[ "$packages" == "0" ]]; then
        show_menu
    elif [[ -z "$packages" ]]; then
        echo "No packages entered. Please try again."
    else
        echo "Installing: $packages"
        dnf install -y $packages
        add_to_package_list $packages
        echo "Installation completed and package list updated."
    fi
    sleep 3
    show_menu
}

add_to_package_list() {
    for package in "$@"; do
        if ! grep -qx "$package" "$PACKAGE_LIST_FILE"; then
            echo "$package" >> "$PACKAGE_LIST_FILE"
        fi
    done
    # Sort the package list alphabetically and remove duplicates
    sort -u -o "$PACKAGE_LIST_FILE" "$PACKAGE_LIST_FILE"
}

# ----- Other Utility Functions -----

change_shell() {
    echo "Available shells:"
    local shells=($(chsh -l))
    for i in "${!shells[@]}"; do
        echo "$((i+1))) ${shells[$i]}"
    done
    echo "0) Return to the main menu"
    read -rp "Enter the number of the shell you want to set, or press 0 to return: " shell_choice
    if [[ $shell_choice == "0" ]]; then
        show_menu
    elif [[ $shell_choice -ge 1 && $shell_choice -le ${#shells[@]} ]]; then
        selected_shell=${shells[$((shell_choice-1))]}
        echo "Changing the default shell to $selected_shell"
        chsh -s "$selected_shell"
        echo "Default shell changed to $selected_shell. Please log out and log back in for changes to take effect."
    else
        echo "Invalid choice. Please try again."
        sleep 3
        change_shell
    fi
    sleep 3
    show_menu
}

reinstall_from_exported_list() {
    if [[ ! -f $PACKAGE_LIST_FILE ]]; then
        echo "No package list found. Install some packages first."
        sleep 3
        show_menu
        return
    fi

    mapfile -t package_list < "$PACKAGE_LIST_FILE"
    if [[ ${#package_list[@]} -eq 0 ]]; then
        echo "The package list is empty."
        sleep 3
        show_menu
        return
    fi
    echo "Packages in the saved list:"
    for i in "${!package_list[@]}"; do
        echo "$((i+1))) ${package_list[$i]}"
    done
    echo "Enter the numbers of the packages you want to **exclude** (space-separated),"
    echo "press Enter to install all, or enter 0 to return to the main menu:"
    read -rp "Exclude: " exclude_input

    if [[ "$exclude_input" == "0" ]]; then
        echo "Returning to main menu..."
        sleep 1
        show_menu
        return
    fi

    if [[ -n "$exclude_input" ]]; then
        exclude_indexes=($exclude_input)
        filtered_packages=()
        for i in "${!package_list[@]}"; do
            if [[ ! " ${exclude_indexes[@]} " =~ " $((i+1)) " ]]; then
                filtered_packages+=("${package_list[$i]}")
            else
                echo "Skipping: ${package_list[$i]}"
            fi
        done
    else
        filtered_packages=("${package_list[@]}")
    fi

    if [[ ${#filtered_packages[@]} -gt 0 ]]; then
        echo "Installing selected packages: ${filtered_packages[*]}"
        dnf install -y "${filtered_packages[@]}"
        echo "Installation completed."
    else
        echo "No packages selected for installation."
    fi
    sleep 3
    show_menu
}

set_battery_threshold() {
    echo "Enter the maximum battery charge threshold (1-100), or press 0 to return to the main menu (Default: 80%):"
    read -rp "Threshold: " threshold
    if [[ -z "$threshold" ]]; then
        threshold=80
        echo "No input detected. Defaulting to 80%."
    fi
    if [[ "$threshold" == "0" ]]; then
        show_menu
    elif [[ ! "$threshold" =~ ^[0-9]+$ || "$threshold" -gt 100 || "$threshold" -le 0 ]]; then
        echo "Invalid input. Please enter a number between 1 and 100."
    else
        echo "Setting battery charge threshold to $threshold%..."
        for bat in /sys/class/power_supply/BAT?/charge_control_end_threshold; do
            if [[ -f $bat ]]; then
                echo $threshold | tee $bat > /dev/null
                echo "Threshold applied instantly to $bat"
            fi
        done
        service_content="[Unit]
Description=Set battery charge threshold
After=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo $threshold > /sys/class/power_supply/BAT?/charge_control_end_threshold'

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
"
        echo "$service_content" | tee /etc/systemd/system/battery-manager.service > /dev/null
        systemctl enable battery-manager.service
        systemctl start battery-manager.service
        echo "Battery charging threshold set to $threshold% and will persist after reboot."
    fi
    sleep 3
    show_menu
}

configure_git() {
    echo "Enter your Git user name:"
    read -rp "User Name: " git_user
    echo "Enter your Git email:"
    read -rp "Email: " git_email
    if [[ -n "$git_user" && -n "$git_email" ]]; then
        git config --global user.name "$git_user"
        git config --global user.email "$git_email"
        echo "Git configured globally with:"
        git config --global --list | grep 'user'
    else
        echo "Invalid input. Both user name and email are required."
    fi
    sleep 3
    show_menu
}

install_zimfw_online() {
    echo "Installing ZimFW using curl..."
    curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh
    echo "ZimFW installation complete."
    sleep 3
    show_menu
}

install_rpmfusion_ffmpeg() {
    # Detect Fedora version
    local fedora_ver
    fedora_ver=$(rpm -E %fedora)

    echo "🔹 Installing RPM Fusion Free Repo for Fedora $fedora_ver..."
    sudo dnf install -y \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm"

    echo "🔹 Installing RPM Fusion Nonfree Repo for Fedora $fedora_ver..."
    sudo dnf install -y \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"

    echo "🔹 Swapping ffmpeg-free with ffmpeg..."
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing

    echo "Done: RPM Fusion installed and ffmpeg ready."
}


organize_downloads() {
    local SCRIPT_NAME="organize_downloads"
    local SCRIPT_SOURCE="$SCRIPT_DIR/scripts/download_organizer.sh"
    local TARGET_DIR="/usr/local/bin"
    local TARGET_PATH="$TARGET_DIR/$SCRIPT_NAME"
    if [[ ! -f "$SCRIPT_SOURCE" ]]; then
        echo "Error: Source script ($SCRIPT_SOURCE) not found!"
        return 1
    fi
    if [[ -f "$TARGET_PATH" ]]; then
        echo "Script already exists at $TARGET_PATH. Not overwriting."
        return 1
    fi
    echo "Copying script to $TARGET_PATH..."
    cp "$SCRIPT_SOURCE" "$TARGET_PATH"
    chmod +x "$TARGET_PATH"
    echo "Script installed at $TARGET_PATH. Run it using: organize_downloads"
    sleep 3
    show_menu
}

add_shell_alias() {
    echo "Enter the alias name:"
    read alias_name
    echo "Enter the command for alias '$alias_name':"
    read alias_command
    if [[ -z "$alias_name" || -z "$alias_command" ]]; then
        echo "Alias name or command cannot be empty."
        return 1
    fi
    if [[ "$SHELL" == */zsh ]]; then
        config_file="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then
        config_file="$HOME/.bashrc"
    else
        echo "Unsupported shell: $SHELL"
        return 1
    fi
    if grep -q "alias $alias_name=" "$config_file"; then
        echo "Alias '$alias_name' already exists in $config_file."
        return 1
    fi
    echo "alias $alias_name='$alias_command'" >> "$config_file"
    echo "Alias added to $config_file: alias $alias_name='$alias_command'"
    echo "Restart your shell or run: source $config_file for changes to take effect."
    sleep 3
    show_menu
}

copy_dnf_config() {
  
  # Backup dnf.conf before editing
  cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak

  cp etc/dnf.conf /etc/dnf/dnf.conf

  dnf upgrade
  
  echo "Dnf config restored to /etc/dnf/dnf.conf"
}

move_config_to_home() {
    local source_dir="$SCRIPT_DIR/config"
    local target_dir="$HOME/.config"
    if [[ ! -d "$source_dir" ]]; then
        echo "No 'config' directory found in the script directory ($source_dir)."
        sleep 2
        show_menu
        return
    fi
    mkdir -p "$target_dir"
    shopt -s dotglob nullglob
    local files=("$source_dir"/*)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "'config' directory is empty. Nothing to move."
        sleep 2
        show_menu
        return
    fi
    echo "Moving contents of $source_dir to $target_dir..."
    mv "$source_dir"/* "$target_dir"/
    echo "Config files moved to $target_dir."
    sleep 2
    show_menu
}


# ----- MENU -----

show_menu() {
    clear
    echo "Arch Linux Setup Script"
    echo "======================="

    local options=()
    options+=("Copy DNF config:copy_dnf_config")
    options+=("Update system:update_system")

    options+=("Install packages:install_packages")
    if [[ -f "$PACKAGE_LIST_FILE" && -s "$PACKAGE_LIST_FILE" ]]; then
        options+=("Install packages from saved list:reinstall_from_exported_list")
    fi

    options+=("Install non-free drivers from rpm-fusion")
    options+=("Copy config files:move_config_to_home")
    options+=("Change default shell:change_shell")
    options+=("Add aliases:add_shell_alias")

    if [[ "$USER_SHELL" == */zsh && ! -f "$HOME/.zimrc" ]]; then
        options+=("Install ZimFW:install_zimfw_online")
    fi

    options+=("Set battery charging threshold (Default 80%):set_battery_threshold")
    options+=("Configure Git user name and email:configure_git")

    if [[ ! -f "/usr/local/bin/organize_downloads" ]]; then
        options+=("Install Downloads Organizer Script:organize_downloads")
    fi

    local index=1
    for option in "${options[@]}"; do
        echo "$index) ${option%%:*}"
        ((index++))
    done
    echo "0) Exit"
    echo "======================="

    read -rp "Enter your choice: " choice

    if [[ "$choice" -ge 1 && "$choice" -le ${#options[@]} ]]; then
        eval "${options[$((choice - 1))]#*:}"
    elif [[ "$choice" == "0" ]]; then
        echo "Exiting..."
        exit 0
    else
        echo "Invalid choice. Please try again."
        sleep 2
        show_menu
    fi
}

# Start the script by calling the menu
show_menu

