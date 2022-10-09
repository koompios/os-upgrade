#!/bin/bash

# Colors
NC='\033[0m' # No Color
RED='\033[0;31m'
BLACK='\033[0;30m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPEL='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'

smart_install_retries=0
smart_update_retries=0
continues=1
completed=0

PASSWORD="";

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

checkpw

function as_su() {
    sudo -S <<< $PASSWORD $@
}

function spinner() {
    local info="$1"
    local pid=$!
    local delay=0.5
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[${YELLOW}%c${NC}] $info" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        local reset="\b\b\b\b\b\b"
        for ((i = 1; i <= $(echo $info | wc -c); i++)); do
            reset+="\b"
        done
        printf $reset
    done

    printf "[${GREEN}\xE2\x9C\x94${NC}]"
    echo -e ""
}

function smart_update() {
    # prevent stale becuase of db lock
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

function smart_install() {
    # prevent stale becuase of db lock
    [[ -f "/var/lib/pacman/db.lck" ]] && as_su rm -rf /var/lib/pacman/db.lck
    if [[ $smart_install_retries > 0 ]]; then
        [[ $smart_install_retries < 5 ]] && echo -e "\n${GREEN}Smart install pass: $smart_install_retries${NC}" || echo -e "\n${YELLOW}Smart install pass: $smart_install_retries${NC}"
    fi

    as_su pacman -Syy >/dev/null 2>&1
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

function smart_remove() {
    for pkg in $@; do
        as_su pacman -Qi $pkg > /dev/null 2>&1
        [[ $? -eq 0 ]] && as_su pacman -Rdd --noconfirm $pkg > /dev/null 2>&1 >> /tmp/uninstallation.log
    done
}

function insert_koompi_repo() {
    grep "dev.koompi.org" /etc/pacman.conf >/dev/null 2>&1
    [[ $? -eq 1 ]] && echo -e '\n[koompi]\nSigLevel = Never\nServer = https://dev.koompi.org/koompi\n' | sudo tee -a /etc/pacman.conf >/dev/null 2>&1
}

function refresh_mirror() {
    insert_koompi_repo;

    as_su sed -i 's/Required[[:space:]]DatabaseOptional/Never/g' /etc/pacman.conf >/dev/null 2>&1
    as_su sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist

    smart_install archlinux-keyring

    as_su pacman -Qi reflector >/dev/null 2>&1
    [[ $? -eq 1 ]] && smart_install reflector
    as_su reflector --latest 20 --protocol https --sort rate --download-timeout 10 --save /etc/pacman.d/mirrorlist >/dev/null 2>&1
    as_su sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist
    echo -e "--latest 20 --protocol https --sort rate --download-timeout 10 --save" | tee /etc/xdg/reflector/reflector.conf >/dev/null 2>&1
}

function install_upgrade() {
    smart_install \
        linux \
        linux-headers \
        linux-firmware \
        acpi \
        acpi_call \
        dkms \
        grub \
        ttf-ms-fonts \
        ttf-vista-fonts \
        khmer-fonts \
        wireplumber \
        libinput \
        xf86-input-libinput;

    # release config
    echo -e "[General]\nName=KOOMPI OS\nPRETTY_NAME=KOOMPI OS\nLogoPath=/usr/share/icons/koompi/koompi.svg\nWebsite=http://www.koompi.com\nVersion=2.8.0\nVariant=Rolling Release\nUseOSReleaseVersion=false" | sudo tee /etc/xdg/kcm-about-distrorc >/dev/null 2>&1
    echo -e 'NAME="KOOMPI OS"\nPRETTY_NAME="KOOMPI OS"\nID=koompi\nBUILD_ID=rolling\nANSI_COLOR="38;2;23;147;209"\nHOME_URL="https://www.koompi.com/"\nDOCUMENTATION_URL="https://wiki.koompi.org/"\nSUPPORT_URL="https://t.me/koompi"\nBUG_REPORT_URL="https://t.me/koompi"\nLOGO=/usr/share/icons/koompi/koompi.svg' | sudo tee /etc/os-release >/dev/null 2>&1
}

function remove_dropped_packages() {
    # Workaround: install wireplumber before update to prevent smart_update
    # recursive hell due to inabiblity to select default package by --noconfirm
    smart_install wireplumber

    smart_remove \
        pipewire-media-session \
        koompi-linux \
        koompi-linux-headers \
        koompi-linux-docs \
        acpi_call-koompi-linux \
        koompi-libinput \
        koompi-xf86-input-libinput \
        sel-protocol \
        handbrake \
        pipewire-jack \
        bind-tools \
        clonezilla \
        darkhttpd \
        ddrescue \
        espeakup \
        fcitx5-chewing \
        fcitx5-rime \
        lftp \
        livecd-sound \
        lynx \
        mkinitcpio-archiso \
        nbd \
        openconnect \
        pptpclient \
        rp-pppoe \
        wvdial \
        xl2tpd \
        tcpdump \
        vpnc \
        pulseaudio \
        pulseaudio-alsa \
        pulseaudio-jack \
        pulseaudio-bluetooth;
}

function update_grub() {
    as_su rm -rf /boot/efi/* /boot/grub/*
    smart_install grub;
    as_su mkinitcpio -P >/dev/null 2>&1
    as_su grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=KOOMPI_OS >/dev/null 2>&1
    as_su grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
}

function apply_config() {
    # Reapply skel to fix broken key bind issue
    cp -r /etc/skel/.config $HOME
}

function prevent_power_management() {
    as_su systemctl --quiet --runtime mask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
}

function allow_power_management() {
    as_su systemctl --quiet --runtime unmask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
}

echo -e "${CYAN}====================================================================== ${NC}"
echo -e "${CYAN} ██╗  ██╗ ██████╗  ██████╗ ███╗   ███╗██████╗ ██╗     ██████╗ ███████╗ ${NC}"
echo -e "${CYAN} ██║ ██╔╝██╔═══██╗██╔═══██╗████╗ ████║██╔══██╗██║    ██╔═══██╗██╔════╝ ${NC}"
echo -e "${CYAN} █████╔╝ ██║   ██║██║   ██║██╔████╔██║██████╔╝██║    ██║   ██║███████╗ ${NC}"
echo -e "${CYAN} ██╔═██╗ ██║   ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██║    ██║   ██║╚════██║ ${NC}"
echo -e "${CYAN} ██║  ██╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ██║    ╚██████╔╝███████║ ${NC}"
echo -e "${CYAN} ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝     ╚═════╝ ╚══════╝ ${NC}"
echo -e "${CYAN}====================================================================== ${NC}"
echo -e ""
echo -e "Upgrade to version 2.8.0"
echo -e "Initialzing generation upgrade"
echo -e ""
prevent_power_management
echo -e "${RED}NOTE: During update, do not turn off your computer.${NC}"
echo -e ""

if [[ $continues -eq 1 ]]; then
    (refresh_mirror) &
    spinner "Ranking mirror repositories"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (remove_dropped_packages) &
    spinner "Removing dropped packages"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (smart_update) &
    spinner "Updating all installed applications"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (install_upgrade) &
    spinner "Upgrading to KOOMPI OS 2.8.0"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (apply_config) &
    spinner "Updating configurations"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (update_grub) &
    spinner "Updating bootloader"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    echo -e ""
    allow_power_management
    echo -e "${CYAN}====================================================================== ${NC}"
    echo -e ""
    echo -e "${GREEN}Upgraded to version 2.8.0${NC}"
    echo -e "${YELLOW}Please restart your computer before continue using.${NC}"
    echo -e ""
else
    echo -e ""
    allow_power_management
    echo -e "${RED}====================================================================== ${NC}"
    echo -e ""
    echo -e "${RED}Upgraded failed${NC}"
    echo -e "${YELLOW}${completed} steps was completed"
    echo -e "There was many attemps to solve the issue but still unable to automatically fix."
    echo -e "${RED}Please run:${NC}"
    echo -e ""
    echo -e "${RED}sudo pacman -Syyu${NC}"
    echo -e ""
    echo -e "${RED}Then restart your computer${NC}"
    echo -e ""
fi

# To set presentation mode
# inhibit_cookie=$(qdbus org.freedesktop.PowerManagement.Inhibit /org/freedesktop/PowerManagement/Inhibit org.freedesktop.PowerManagement.Inhibit.Inhibit "a name" "a reason")

# To unset presentation mode
# qdbus org.freedesktop.PowerManagement.Inhibit /org/freedesktop/PowerManagement/Inhibit org.freedesktop.PowerManagement.Inhibit.UnInhibit $inhibit_cookie

