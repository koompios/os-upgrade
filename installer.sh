#!/bin/bash

# Colors
NC='\033[0m' # No Color
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'

# Global variables
smart_install_retries=0
smart_update_retries=0
continues=1
completed=0
PASSWORD=""
CURRENT_TIME=$(date +"%d-%m-%y-%H-%m-%S")

# Main function
main() {
    echo -e "${CYAN}====================================================================== ${NC}"
    echo -e "${CYAN} ██╗  ██╗ ██████╗  ██████╗ ███╗   ███╗██████╗ ██╗     ██████╗ ███████╗ ${NC}"
    echo -e "${CYAN} ██║ ██╔╝██╔═══██╗██╔═══██╗████╗ ████║██╔══██╗██║    ██╔═══██╗██╔════╝ ${NC}"
    echo -e "${CYAN} █████╔╝ ██║   ██║██║   ██║██╔████╔██║██████╔╝██║    ██║   ██║███████╗ ${NC}"
    echo -e "${CYAN} ██╔═██╗ ██║   ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██║    ██║   ██║╚════██║ ${NC}"
    echo -e "${CYAN} ██║  ██╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ██║    ╚██████╔╝███████║ ${NC}"
    echo -e "${CYAN} ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝     ╚═════╝ ╚══════╝ ${NC}"
    echo -e "${CYAN}====================================================================== ${NC}\n"
    echo -e "Upgrade to version 3.0.0\nInitializing upgrade process\n"
    echo -e "${RED}NOTE: During the update, do not turn off your computer.${NC}\n"


    checkpw
    setup_log
    prevent_power_management

    echo -e "${CYAN}====================================================================== ${NC}\n"
    echo -e "${YELLOW}Step 1: Ranking mirror repositories${NC}\n"
    refresh_mirror

    echo -e "${CYAN}====================================================================== ${NC}\n"
    echo -e "${YELLOW}Step 2: Removing dropped packages${NC}\n"
    remove_dropped_packages

    echo -e "${CYAN}====================================================================== ${NC}\n"
    echo -e "${YELLOW}Step 3: Updating all installed applications${NC}\n"
    smart_update

    echo -e "${CYAN}====================================================================== ${NC}\n"
    echo -e "${YELLOW}Step 4: Upgrading to KOOMPI OS 3.0.0${NC}\n"
    install_upgrade

    echo -e "${CYAN}====================================================================== ${NC}\n"
    echo -e "${YELLOW}Step 5: Updating configurations${NC}\n"
    apply_config

    echo -e "${CYAN}====================================================================== ${NC}\n"
    echo -e "${YELLOW}Step 6: Updating bootloader${NC}\n"
    update_grub

    logging

    ## Clean up Pacman space
    as_su rm -rf ${HOME}/.cache /var/cache/pacman/pkg/*

    allow_power_management


    if [[ $continues -eq 1 ]]; then
        echo -e "\n${CYAN}====================================================================== ${NC}\n"
        echo -e "${GREEN}Upgrade to version 3.0.0 completed${NC}"
        echo -e "${YELLOW}Please restart your computer before continuing to use.${NC}\n"

    else
        echo -e "\n${RED}====================================================================== ${NC}\n"
        echo -e "${RED}Upgrade failed${NC}"
        echo -e "\n${YELLOW}${completed} steps were completed"
        echo -e "There were many attempts to solve the issue but still unable to automatically fix.\n"
        echo -e "${RED}Please run:${NC}\n${RED}sudo pacman -Syyu${NC}\n\n${RED}Then restart your computer${NC}\n"
    fi
}

function setup_log() {
    as_su mkdir -p /var/log/koompi-os-upgrade-${CURRENT_TIME} -m 770
    as_su chown $USER:users /var/log/koompi-os-upgrade-${CURRENT_TIME}
}

function logging() {
    cp /tmp/update.log /var/log/koompi-os-upgrade-${CURRENT_TIME} >/dev/null 2>&1
    cp /tmp/installation.log /var/log/koompi-os-upgrade-${CURRENT_TIME} >/dev/null 2>&1
    cp /tmp/boot.log /var/log/koompi-os-upgrade-${CURRENT_TIME} >/dev/null 2>&1
}

function checkpw() {
    IFS= read -p "Enter your password: " PASSWD
    sudo -k
    if sudo -lS <<< $PASSWD &> /dev/null;
    then
        PASSWORD=$PASSWD
        clear;
    else
        faillock --user $USER --reset
        echo 'Invalid password. Try again!'
        checkpw
    fi
}

function as_su() {
    sudo -S <<< $PASSWORD $@
}

function spinner() {
    local info="$1"
    local info_byte_count=$(echo $info | wc -c 2>/dev/null) || info_byte_count=32
    local pid=$!
    local delay=0.5
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[${YELLOW}%c${NC}] $info" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay 2>/dev/null
        local reset="\b\b\b\b\b\b"
        for ((i = 1; i <= $info_byte_count; i++)); do
            reset+="\b"
        done
        printf $reset
    done

    printf "[${GREEN}\xE2\x9C\x94${NC}]"
    echo -e ""
}

function smart_update() {
    # prevent stale because of db lock
    [[ -f "/var/lib/pacman/db.lck" ]] && as_su rm -rf /var/lib/pacman/db.lck
    if [[ $smart_update_retries > 0 ]]; then
        [[ $smart_update_retries < 5 ]] && echo -e "\n${GREEN}Smart update pass: $smart_update_retries${NC}" || echo -e "\n${YELLOW}Smart update pass: $smart_update_retries${NC}"
    fi
    as_su pacman -Syyu --noconfirm --overwrite="*" >/dev/null 2>&1 >/tmp/update.log
    if [[ $? -eq 1 ]]; then
        as_su find /var/cache/pacman/pkg/ -iname "*.part" -delete >/dev/null 2>&1

        local conflict_files=($(cat /tmp/update.log | grep "exists in filesystem" | grep -o '/[^ ]*'))

        if [[ ${#conflict_files[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict files detected. Resolving conflict files${NC}"
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                as_su rm -rf ${conflict_files[$i]}
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Removed: ${conflict_files[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to remove: ${conflict_files[$i]} ${NC}"
                fi
            done
        fi

        local conflict_packages=($(cat /tmp/update.log | grep 'are in conflict' | grep -o 'Remove [^ ]*' | grep -oE '[^ ]+$' | sed -e "s/[?]//"))

        if [[ ${#conflict_packages[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict packages detected. Resovling conflict packages.${NC}"
            for ((i = 0; i < ${#conflict_packages[@]}; i++)); do
                as_su pacman -Rdd --noconfirm ${conflict_packages[$i]} >/dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Uninstalled: ${conflict_packages[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to uninstall: ${conflict_packages[$i]} ${NC}"
                fi
            done
        fi

        local breakers=($(cat /tmp/update.log | grep " breaks dependency " | grep -o 'required by [^ ]*' | grep -oE '[^ ]+$'))

        if [[ ${#breakers[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict dependencies detected. Resovling conflicting dependencies.${NC}"
            for ((i = 0; i < ${#breakers[@]}; i++)); do
                as_su pacman -Rdd --noconfirm ${breakers[$i]} >/dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Uninstalled: ${breakers[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to uninstall: ${breakers[$i]} ${NC}"
                fi
            done
        fi

        local satisfiers=($(cat /tmp/update.log | grep "unable to satisfy dependency" | grep -oE '[^ ]+$'))

        if [[ ${#satisfiers[@]} -gt 0 ]]; then
            echo -e "\n${YELLOW}Unsatisfied depencies detected. Resovling issues.${NC}"
            for ((i = 0; i < ${#satisfiers[@]}; i++)); do
                as_su pacman -Rdd --noconfirm ${satisfiers[$i]} >/dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Uninstalled: ${satisfiers[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to uninstall: ${satisfiers[$i]} ${NC}"
                fi
            done
        fi

        cp /tmp/update.log "/tmp/update${smart_update_retries}.log"
        smart_update_retries=$((smart_update_retries + 1))

        if [[ $smart_update_retries -lt 30 ]]; then
            smart_update
        else
            continues=0
        fi
    fi

}

smart_install_packages() {
    # Increment the smart_install_pass counter
    smart_install_pass=$((smart_install_pass + 1))

    # prevent stale becuase of db lock
    [[ -f "/var/lib/pacman/db.lck" ]] && as_su rm -rf /var/lib/pacman/db.lck
    if [[ $smart_install_retries > 0 ]]; then
        [[ $smart_install_retries < 5 ]] && echo -e "\n${GREEN}Smart install pass: $smart_install_retries${NC}" || echo -e "\n${YELLOW}Smart install pass: $smart_install_retries${NC}"
    fi


    # Read each line from the packages file and call smart_install function
    while IFS= read -r package; do
        # Ignore lines starting with '#' (comments or section headings)
        if [[ "$package" =~ ^# ]]; then
            continue
        fi

        # Trim leading and trailing whitespace
        package=$(echo "$package" | xargs)

        # Check if the package is not empty
        if [ -n "$package" ]; then
            # Call smart_install function for each package
            smart_install "$package"
        fi
    done < "install_packages"
}



function smart_install() {
    # prevent stale becuase of db lock
    [[ -f "/var/lib/pacman/db.lck" ]] && as_su rm -rf /var/lib/pacman/db.lck
    if [[ $smart_install_retries > 0 ]]; then
        [[ $smart_install_retries < 5 ]] && echo -e "\n${GREEN}Smart install pass: $smart_install_retries${NC}" || echo -e "\n${YELLOW}Smart install pass: $smart_install_retries${NC}"
    fi

    # as_su pacman -Syy >/dev/null 2>&1
    as_su pacman -S --needed --noconfirm $@ --overwrite="*" > /dev/null 2>&1 >/tmp/installation.log

    if [[ $? -eq 1 ]]; then
        as_su find /var/cache/pacman/pkg/ -iname "*.part" -delete >/dev/null 2>&1

        local conflict_files=($(cat /tmp/installation.log | grep "exists in filesystem" | grep -o '/[^ ]*'))

        if [[ ${#conflict_files[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict files detected. Resolving conflict files${NC}"
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                as_su rm -rf ${conflict_files[$i]}
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Removed: ${conflict_files[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to remove: ${conflict_files[$i]} ${NC}"
                fi
            done
        fi

        local conflict_packages=($(cat /tmp/installation.log | grep 'are in conflict' | grep -o 'Remove [^ ]*' | grep -oE '[^ ]+$' | sed -e "s/[?]//"))

        if [[ ${#conflict_packages[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict packages detected. Resovling conflict packages.${NC}"
            for ((i = 0; i < ${#conflict_packages[@]}; i++)); do
                as_su pacman -Rdd --noconfirm ${conflict_packages[$i]} >/dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Uninstalled: ${conflict_packages[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to uninstall: ${conflict_packages[$i]} ${NC}"
                fi
            done
        fi

        local breakers=($(cat /tmp/installation.log | grep " breaks dependency " | grep -o 'required by [^ ]*' | grep -oE '[^ ]+$'))

        if [[ ${#breakers[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict dependencies detected. Resovling conflicting dependencies.${NC}"
            for ((i = 0; i < ${#breakers[@]}; i++)); do
                as_su pacman -Rdd --noconfirm ${breakers[$i]} >/dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Uninstalled: ${breakers[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to uninstall: ${breakers[$i]} ${NC}"
                fi
            done
        fi

        local satisfiers=($(cat /tmp/installation.log | grep "unable to satisfy dependency" | grep -oE '[^ ]+$'))

        if [[ ${#satisfiers[@]} -gt 0 ]]; then
            echo -e "\n${YELLOW}Unsatisfied depencies detected. Resovling issues.${NC}"
            for ((i = 0; i < ${#satisfiers[@]}; i++)); do
                as_su pacman -Rdd --noconfirm ${satisfiers[$i]} >/dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Uninstalled: ${satisfiers[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to uninstall: ${satisfiers[$i]} ${NC}"
                fi
            done
        fi

        cp /tmp/installation.log "/tmp/installation${smart_install_retries}.log"
        smart_install_retries=$((smart_install_retries + 1))

        if [[ $smart_install_retries -lt 30 ]]; then
            smart_install $@
        else
            continues=0
        fi
    fi

}

smart_remove_packages() {
    # Check if the packages file exists
    if [ ! -f "remove_packages" ]; then
        echo "Error: Packages file 'packages' not found."
        return 1
    fi

    # Read each line from the packages file and call smart_install function
    while IFS= read -r package; do
        # Ignore lines starting with '#' (comments or section headings)
        if [[ "$package" =~ ^# ]]; then
            continue
        fi

        # Trim leading and trailing whitespace
        package=$(echo "$package" | xargs)

        # Check if the package is not empty
        if [ -n "$package" ]; then
            # Call smart_remove function for each package
            smart_remove "$package"
        fi
    done < "remove_packages"
}


function smart_remove() {
    for pkg in $@; do
        as_su pacman -Qi $pkg > /dev/null 2>&1
        [[ $? -eq 0 ]] && as_su pacman -Rdd --noconfirm $pkg > /dev/null 2>&1 >> /tmp/uninstallation.log
    done
}

function insert_koompi_repo() {
    if ! awk '/^\s*\[koompi\]/ { in_block = 0 } /^\s*\[koompi\]/ { in_block = 1 } in_block && !/^\s*#/ { found = 1 } END { exit !found }' /etc/pacman.conf; then
        echo -e '\n[koompi]\nSigLevel = Never\nServer = https://dev.koompi.org/koompi\n' | sudo tee -a /etc/pacman.conf >/dev/null 2>&1
    fi

}

function refresh_mirror() {
    insert_koompi_repo;

    as_su sed -i 's/Required[[:space:]]DatabaseOptional/Never/g' /etc/pacman.conf >/dev/null 2>&1
    as_su sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist

    smart_install archlinux-keyring

as_su pacman -Qi reflector >/dev/null 2>&1
[[ $? -eq 1 ]] && smart_install reflector

echo -e "--latest 5 --protocol https --sort rate --download-timeout 10 --save" | tee /etc/xdg/reflector/reflector.conf >/dev/null 2>&1

local CHECK_LOCAL_MIRROR=$(getent hosts "mirror.koompi.org" | awk 'NR==1' | awk '{ print $1 }')

if [[ "${CHECK_LOCAL_MIRROR}" =~ 10+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Server = https://mirror.koompi.org/archlinux/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist >/dev/null 2>&1
else
    # Replace the reflector commands with the predefined mirrorlist
    cat <<EOF | sudo tee /etc/pacman.d/mirrorlist >/dev/null 2>&1
################################################################################

## Cambodia
Server = http://mirror.sabay.com.kh/archlinux/\$repo/os/\$arch
Server = https://mirror.sabay.com.kh/archlinux/\$repo/os/\$arch
## Vietnam
Server = http://mirror.bizflycloud.vn/archlinux/\$repo/os/\$arch
Server = http://mirror.kirbee.tech/archlinux/\$repo/os/\$arch
## Singapore
Server = http://mirror.0x.sg/archlinux/\$repo/os/\$arch
Server = https://mirror.0x.sg/archlinux/\$repo/os/\$arch
Server = http://mirror.aktkn.sg/archlinux/\$repo/os/\$arch
Server = https://mirror.aktkn.sg/archlinux/\$repo/os/\$arch
Server = http://sg.mirrors.cicku.me/archlinux/\$repo/os/\$arch
## Japan
Server = http://mirrors.cat.net/archlinux/\$repo/os/\$arch
Server = https://mirrors.cat.net/archlinux/\$repo/os/\$arch
EOF

    # Remove any entries containing '0x.sg'
    as_su sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist
fi

}

function install_upgrade() {
    smart_remove networkmanager-iwd;
    smart_install_packages

    # release config
    # # Remove /etc/os-release and install the KOOMPI-OS package instead
    # echo -e "[General]\nName=KOOMPI OS\nPRETTY_NAME=KOOMPI OS\nLogoPath=/usr/share/icons/koompi/koompi.svg\nWebsite=http://www.koompi.com\nVersion=2.8.1\nVariant=Rolling Release\nUseOSReleaseVersion=false" | sudo tee /etc/xdg/kcm-about-distrorc >/dev/null 2>&1
    # echo -e 'NAME="KOOMPI OS"\nPRETTY_NAME="KOOMPI OS"\nID=koompi\nBUILD_ID=rolling\nANSI_COLOR="38;2;23;147;209"\nHOME_URL="https://www.koompi.com/"\nDOCUMENTATION_URL="https://wiki.koompi.org/"\nSUPPORT_URL="https://t.me/koompi"\nBUG_REPORT_URL="https://t.me/koompi"\nLOGO=/usr/share/icons/koompi/koompi.svg' | sudo tee /etc/os-release >/dev/null 2>&1
    # echo -e '[device]\nwifi.backend=iwd\n' | sudo tee /etc/NetworkManager/conf.d/iwd.conf >/dev/null 2>&1
}

function remove_dropped_packages() {
    # Workaround: install wireplumber before update to prevent smart_update
    # recursive hell due to inabiblity to select default package by --noconfirm
    # UPDATE: Added CALAMARES due to old version install it without pacman and leave leftover file without install
    # smart_install wireplumber koompi-calamares
    smart_remove_packages
    smart_remove \

}

function update_grub() {
    boot=($(lsblk --list --fs | grep FAT32))
    boot_drive=/dev/${boot[0]}
    old_boot_drive_uuid=$(lsblk -o uuid $boot_drive | grep -v UUID)

    echo boot_drive=${boot_drive} >>/tmp/boot.log
    echo -e "old_boot_drive_uuid=${old_boot_drive_uuid}\n" >>/tmp/boot.log

    as_su umount $boot_drive && echo Unmounted $boot_drive >>/tmp/boot.log
    as_su mkfs.fat -F32 $boot_drive &>>/tmp/boot.log

    as_su systemctl daemon-reload
    new_boot_drive_uuid=$(lsblk -o uuid $boot_drive | grep -v UUID)

    ## The operation is too fast that the UUID doesn't change fast enough causing query of new uuid
    ## to be the same as old. This caused mount to fail and subsequently grub-install would fail
    ## leading to system unbootable. Therefore, this loop requery the UUID until it changes.
    while true;
    do
        if [[ ${new_boot_drive_uuid} == ${old_boot_drive_uuid} ]];
        then
            sleep 5;
            new_boot_drive_uuid=$(lsblk -o uuid $boot_drive | grep -v UUID);
        else
            break;
        fi
    done

    as_su mount -U ${new_boot_drive_uuid} /boot/efi && echo -e "Mounted $boot_drive\n" >>/tmp/boot.log

    echo new_boot_drive_uuid=${new_boot_drive_uuid} >>/tmp/boot.log
    echo -e "\n====================================== old fstab ====================================" >>/tmp/boot.log
    as_su cat /etc/fstab &>>/tmp/boot.log
    echo -e "=====================================================================================\n" >>/tmp/boot.log

    as_su sed -i "s/$old_boot_drive_uuid/$new_boot_drive_uuid/g" /etc/fstab

    echo "====================================== new fstab ====================================" >>/tmp/boot.log
    as_su cat /etc/fstab &>>/tmp/boot.log
    echo -e "=====================================================================================\n" >>/tmp/boot.log

    smart_install grub;
    as_su mkinitcpio -P &>>/tmp/boot.log

    echo "" >>/tmp/boot.log
    as_su grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=KOOMPI_OS --recheck &>>/tmp/boot.log

    echo "" >>/tmp/boot.log
    as_su grub-mkconfig -o /boot/grub/grub.cfg &>>/tmp/boot.log
}

function apply_config() {
    # Reapply skel to fix broken key bind issue
    # UPDATE: Added bashrc and bash profile to fix some fcitx5 issue
    as_su cp -r -T /etc/skel/ ${HOME}
    as_su chown ${USER}:users -R ${HOME} &>/dev/null
    #as_su usermod -aG realtime ${USER}

    ## Set metadata
    #for file in $HOME/Desktop/*.desktop; do
    #    gio set "$file" metadata::trusted true
    #done

    ## Change permissions
    #for file in $HOME/Desktop/*.desktop; do
    #    as_su chmod a+x "$file"
    #done

}

function prevent_power_management() {
    as_su systemctl --quiet --runtime mask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
}

function allow_power_management() {
    as_su systemctl --quiet --runtime unmask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
}

# Call the main function
main
