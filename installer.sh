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

echo "Enter your password: "  
read sudo_password

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
    [[ -f "/var/lib/pacman/db.lck" ]] && sudo -S <<< "${sudo_password}" rm -rf /var/lib/pacman/db.lck
    if [[ $smart_update_retries > 0 ]]; then
        [[ $smart_update_retries < 5 ]] && echo -e "\n${GREEN}Smart update pass: $smart_update_retries${NC}" || echo -e "\n${YELLOW}Smart update pass: $smart_update_retries${NC}"
    fi
    sudo -S <<< "${sudo_password}" pacman -Syyu --noconfirm --overwrite="*" >/dev/null 2>&1 >/tmp/update.log
    if [[ $? -eq 1 ]]; then
        sudo -S <<< "${sudo_password}" find /var/cache/pacman/pkg/ -iname "*.part" -delete >/dev/null 2>&1

        local conflict_files=($(cat /tmp/update.log | grep "exists in filesystem" | grep -o '/[^ ]*'))

        if [[ ${#conflict_files[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict files detected. Resolving conflict files${NC}"
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                sudo -S <<< "${sudo_password}" rm -rf ${conflict_files[$i]}
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
                sudo -S <<< "${sudo_password}" pacman -Rcc --noconfirm ${conflict_packages[$i]} >/dev/null 2>&1
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
                sudo -S <<< "${sudo_password}" pacman -Rdd --noconfirm ${breakers[$i]} >/dev/null 2>&1
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
                sudo -S <<< "${sudo_password}" pacman -Rdd --noconfirm ${satisfiers[$i]} >/dev/null 2>&1
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
    [[ -f "/var/lib/pacman/db.lck" ]] && sudo -S <<< "${sudo_password}" rm -rf /var/lib/pacman/db.lck
    if [[ $smart_install_retries > 0 ]]; then
        [[ $smart_install_retries < 5 ]] && echo -e "\n${GREEN}Smart install pass: $smart_install_retries${NC}" || echo -e "\n${YELLOW}Smart install pass: $smart_install_retries${NC}"
    fi

    sudo -S <<< "${sudo_password}" pacman -Syy >/dev/null 2>&1
    sudo -S <<< "${sudo_password}" pacman -S --needed --noconfirm $@ --overwrite="*" > /dev/null 2>&1 >/tmp/installation.log

    if [[ $? -eq 1 ]]; then
        sudo -S <<< "${sudo_password}" find /var/cache/pacman/pkg/ -iname "*.part" -delete >/dev/null 2>&1

        local conflict_files=($(cat /tmp/installation.log | grep "exists in filesystem" | grep -o '/[^ ]*'))

        if [[ ${#conflict_files[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict files detected. Resolving conflict files${NC}"
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                sudo -S <<< "${sudo_password}" rm -rf ${conflict_files[$i]}
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
                sudo -S <<< "${sudo_password}" pacman -Rcc --noconfirm ${conflict_packages[$i]} >/dev/null 2>&1
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
                sudo -S <<< "${sudo_password}" pacman -Rdd --noconfirm ${breakers[$i]} >/dev/null 2>&1
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
                sudo -S <<< "${sudo_password}" pacman -Rdd --noconfirm ${satisfiers[$i]} >/dev/null 2>&1
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
        sudo -S <<< "${sudo_password}" pacman -Qi $pkg > /dev/null 2>&1
        [[ $? -eq 0 ]] && sudo -S <<< "${sudo_password}" pacman -Rdd --noconfirm $pkg > /dev/null 2>&1 >> /tmp/uninstallation.log
    done
}

function refresh_mirror() {
    sudo -S <<< "${sudo_password}" sed -i 's/Required[[:space:]]DatabaseOptional/Never/g' /etc/pacman.conf >/dev/null 2>&1
    sudo -S <<< "${sudo_password}" sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist

    smart_install archlinux-keyring

    sudo -S <<< "${sudo_password}" pacman -Qi reflector >/dev/null 2>&1
    [[ $? -eq 1 ]] && smart_install reflector
    sudo -S <<< "${sudo_password}" reflector --latest 30 --protocol https --sort rate --download-timeout 10 --save /etc/pacman.d/mirrorlist >/dev/null 2>&1
    sudo -S <<< "${sudo_password}" sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist
    echo -e "--latest 30 --protocol https --sort rate --download-timeout 10 --save" | tee /etc/xdg/reflector/reflector.conf >/dev/null 2>&1
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
        flat
}

function remove_dropped_packages() {
    smart_remove \
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

    sudo -S <<< "${sudo_password}" sed -i -e 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/g' /etc/default/grub
    sudo -S <<< "${sudo_password}" sed -i -e 's/GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="KOOMPI_OS"/g' /etc/default/grub
    sudo -S <<< "${sudo_password}" sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 rd.udev.log-priority=0 vt.global_cursor_default=0 fsck.mode=skip"/g' /etc/default/grub
    # kernel
    sudo -S <<< "${sudo_password}" sed -i -e "s/HOOKS=\"base udev.*/HOOKS=\"base systemd fsck autodetect modconf block keyboard keymap filesystems\"/g" /etc/mkinitcpio.conf
    sudo -S <<< "${sudo_password}" sed -i -e "s/HOOKS=(base udev.*/HOOKS=\"base systemd fsck autodetect modconf block keyboard keymap filesystems\"/g" /etc/mkinitcpio.conf

    sudo -S <<< "${sudo_password}" mkinitcpio -p linux >/dev/null 2>&1

    grep "StandardOutput=null" /etc/systemd/system/systemd-fsck-root.service >/dev/null 2>&1
    if [[ $? == 1 ]]; then
        echo -e "\nStandardOutput=null\nStandardError=journal+console\n" | sudo -S <<< "${sudo_password}" EDITOR='tee -a' systemctl edit --full systemd-fsck-root.service >/dev/null 2>&1
        echo -e "\nStandardOutput=null\nStandardError=journal+console\n" | sudo -S <<< "${sudo_password}" EDITOR='tee -a' systemctl edit --full systemd-fsck@.service >/dev/null 2>&1
    fi
    [ -d /sys/firmware/efi ] && sudo -S <<< "${sudo_password}" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=KOOMPI_OS
    sudo -S <<< "${sudo_password}" grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
}

function prevent_power_management() {
    sudo -S <<< "${sudo_password}" systemctl --quiet --runtime mask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
}

function allow_power_management() {
    sudo -S <<< "${sudo_password}" systemctl --quiet --runtime unmask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
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

