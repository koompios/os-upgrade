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
    [[ -f "/var/lib/pacman/db.lck" ]] && sudo rm -rf /var/lib/pacman/db.lck
    if [[ $smart_update_retries > 0 ]]; then
        [[ $smart_update_retries < 5 ]] && echo -e "\n${GREEN}Smart update pass: $smart_update_retries${NC}" || echo -e "\n${YELLOW}Smart update pass: $smart_update_retries${NC}"
    fi
    sudo pacman -Syyu --noconfirm >/dev/null 2>&1 >/tmp/update.log
    if [[ $? -eq 1 ]]; then
        sudo find /var/cache/pacman/pkg/ -iname "*.part" -delete >/dev/null 2>&1

        local conflict_files=($(cat /tmp/update.log | grep "exists in filesystem" | grep -o '/[^ ]*'))

        if [[ ${#conflict_files[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict files detected. Resolving conflict files${NC}"
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                sudo rm -rf ${conflict_files[$i]}
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Removed: ${conflict_files[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to remove: ${conflict_files[$i]} ${NC}"
                fi
            done
        fi

        local conflict_packages=($(cat /tmp/update.log | grep "are in conflict. Remove" | grep -o 'Remove [^ ]*' | grep -oE '[^ ]+$' | sed -e "s/[?]//"))

        if [[ ${#conflict_packages[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict packages detected. Resovling conflict packages.${NC}"
            for ((i = 0; i < ${#conflict_packages[@]}; i++)); do
                sudo pacman -Rcc --noconfirm ${conflict_packages[$i]} >/dev/null 2>&1
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
                sudo pacman -Rdd --noconfirm ${breakers[$i]} >/dev/null 2>&1
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
                sudo pacman -Rdd --noconfirm ${satisfiers[$i]} >/dev/null 2>&1
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
    [[ -f "/var/lib/pacman/db.lck" ]] && sudo rm -rf /var/lib/pacman/db.lck
    if [[ $smart_install_retries > 0 ]]; then
        [[ $smart_install_retries < 5 ]] && echo -e "\n${GREEN}Smart install pass: $smart_install_retries${NC}" || echo -e "\n${YELLOW}Smart install pass: $smart_install_retries${NC}"
    fi
    sudo pacman -Syy --noconfirm $@ >/dev/null 2>&1 >/tmp/installation.log
    if [[ $? -eq 1 ]]; then
        sudo find /var/cache/pacman/pkg/ -iname "*.part" -delete >/dev/null 2>&1

        local conflict_files=($(cat /tmp/installation.log | grep "exists in filesystem" | grep -o '/[^ ]*'))

        if [[ ${#conflict_files[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict files detected. Resolving conflict files${NC}"
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                sudo rm -rf ${conflict_files[$i]}
                if [[ $? -eq 0 ]]; then
                    echo -e "\n${GREEN}Removed: ${conflict_files[$i]} ${NC}"
                else
                    echo -e "\n${RED}Failed to remove: ${conflict_files[$i]} ${NC}"
                fi
            done
        fi

        local conflict_packages=($(cat /tmp/installation.log | grep "are in conflict. Remove" | grep -o 'Remove [^ ]*' | grep -oE '[^ ]+$' | sed -e "s/[?]//"))

        if [[ ${#conflict_packages[@]} > 0 ]]; then
            echo -e "\n${YELLOW}Conflict packages detected. Resovling conflict packages.${NC}"
            for ((i = 0; i < ${#conflict_packages[@]}; i++)); do
                sudo pacman -Rcc --noconfirm ${conflict_packages[$i]} >/dev/null 2>&1
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
                sudo pacman -Rdd --noconfirm ${breakers[$i]} >/dev/null 2>&1
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
                sudo pacman -Rdd --noconfirm ${satisfiers[$i]} >/dev/null 2>&1
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

function refresh_mirror() {
    sudo sed -i 's/Required[[:space:]]DatabaseOptional/Never/g' /etc/pacman.conf >/dev/null 2>&1
    sudo sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist
    smart_install archlinux-keyring

    sudo pacman -Qi reflector >/dev/null 2>&1
    [[ $? -eq 1 ]] && smart_install reflector
    sudo reflector --country "Hong Kong" --country Singapore --country Japan --country China --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>&1
    sudo sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist
}

function remove_orphans() {

    sudo pacman -Qi linux-apfs >/dev/null 2>&1
    [[ $? -eq 0 ]] && sudo pacman -Rdd --noconfirm linux-apfs >/dev/null 2>&1
    sudo pacman -Qi hfsprogs >/dev/null 2>&1
    [[ $? -eq 0 ]] && sudo pacman -Rdd --noconfirm hfsprogs >/dev/null 2>&1
    sudo pacman -Qi raptor >/dev/null 2>&1
    [[ $? -eq 0 ]] && sudo pacman -Rdd --noconfirm raptor >/dev/null 2>&1
    sudo pacman -Qi fcitx >/dev/null 2>&1
    [[ $? -eq 0 ]] && sudo pacman -Rcc --noconfirm fcitx-im >/dev/null 2>&1
    sudo pacman -Qi libreoffice-still >/dev/null 2>&1
    [[ $? -eq 0 ]] && sudo pacman -Rcc --noconfirm libreoffice-still >/dev/null 2>&1
    # remove prvoise koompi theme
    sudo pacman -Qi breeze10-kde-git >/dev/null 2>&1
    [[ $? -eq 0 ]] && sudo pacman -Rcc --noconfirm breeze10-kde-git >/dev/null 2>&1

    sudo pacman -Rs $(sudo pacman -Qqtd) --noconfirm --quiet >/dev/null 2>&1

    sudo rm -rf /usr/bin/theme-manager \
        /usr/share/applications/theme-manager.desktop \
        /usr/share/org.koompi.theme.manager \
        /usr/share/sddm/themes/kameleon \
        /usr/share/sddm/themes/McMojave \
        /usr/share/sddm/themes/plasma-chili \
        /usr/share/wallpapers/koompi-dark.svg \
        /usr/share/wallpapers/koompi-light.jpg \
        /usr/share/wallpapers/mosx-dark.jpg \
        /usr/share/wallpapers/mosx-light.jpg \
        /usr/share/wallpapers/winx-dark.jpg \
        /usr/share/wallpapers/winx-light.jpg >/dev/null 2>&1
    [[ -f /etc/sddm.conf ]] && sudo rm -rf /etc/sddm.conf
    rm -rf ${HOME}/.config/Kvantum/Fluent-Dark \
        ${HOME}/.config/Kvantum/Fluent-Light \
        ${HOME}/.config/Kvantum/kvantum.kvconfig \
        ${HOME}/.icons/Bibata_Ice/ \
        ${HOME}/.icons/Bibata_Oil/ \
        ${HOME}/.icons/McMojave-cursors \
        ${HOME}/.Win-8.1-S \
        ${HOME}/.local/share/aurorae/themes/McMojave \
        ${HOME}/.local/share/aurorae/themes/McMojave-light \
        ${HOME}/.local/share/aurorae/color-scheems/McMojave.colors \
        ${HOME}/.local/share/aurorae/color-scheems/McMojaveLight.colors \
        ${HOME}/.local/share/icons/la-capitaine-icon-theme \
        ${HOME}/.local/share/icons/Qogir \
        ${HOME}/.local/share/icons/Qogir-dark \
        ${HOME}/.local/share/plasma/desktoptheme/Helium \
        ${HOME}/.local/share/plasma/desktoptheme/Nilium \
        ${HOME}/.local/share/plasma/desktoptheme/McMojave \
        ${HOME}/.local/share/plasma/desktoptheme/McMojave-light \
        ${HOME}/.local/share/plasma/look-and-feel/org.koompi.theme.koompi-dark \
        ${HOME}/.local/share/plasma/look-and-feel/org.koompi.theme.koompi-light \
        ${HOME}/.local/share/plasma/look-and-feel/org.koompi.theme.koompi-mosx-dark \
        ${HOME}/.local/share/plasma/look-and-feel/org.koompi.theme.koompi-mosx-light \
        ${HOME}/.local/share/plasma/look-and-feel/org.koompi.theme.koompi-winx-dark \
        ${HOME}/.local/share/plasma/look-and-feel/org.koompi.theme.koompi-winx-light \
        ${HOME}/.local/share/plasma/plasmoids/com.github.zren.tiledmenu \
        ${HOME}/.local/share/plasma/plasmoids/org.communia.apptitle \
        ${HOME}/.local/share/plasma/plasmoids/org.kde.plasma.chiliclock \
        ${HOME}/.local/share/plasma/plasmoids/org.kde.plasma.umenu \
        ${HOME}/.local/share/plasma/plasmoids/org.kde.plasma.win7showdesktop \
        ${HOME}/Desktop/theme-manager.desktop >/dev/null 2>&1
}

function insert_koompi_repo() {
    grep "dev.koompi.org" /etc/pacman.conf >/dev/null 2>&1
    [[ $? -eq 1 ]] && echo -e '\n[koompi]\nSigLevel = Never\nServer = https://dev.koompi.org/koompi\n' | sudo tee -a /etc/pacman.conf >/dev/null 2>&1
}

function security_patch() {
    # Change passwrod timeout to 60 minutes
    echo -e 'Defaults timestamp_timeout=60' | sudo EDITOR='tee' visudo -f /etc/sudoers.d/timestamp_timeout >/dev/null 2>&1
    # Enable ***** sudo feedback
    echo -e 'Defaults pwfeedback' | sudo EDITOR='tee' visudo -f /etc/sudoers.d/pwfeedback >/dev/null 2>&1
    # Enable group wheel
    echo -e '%wheel ALL=(ALL) ALL' | sudo EDITOR='tee' visudo -f /etc/sudoers.d/10-installer >/dev/null 2>&1
    # Config faillock
    echo -e 'deny = 10\nunlock_time = 60\neven_deny_root\nroot_unlock_time = 600' | sudo tee /etc/security/faillock.conf >/dev/null 2>&1
    # Kernl message
    echo -e 'kernel.printk = 1 1 1 1' | sudo tee /etc/sysctl.d/20-quiet-printk.conf >/dev/null 2>&1
    # VM for usb
    echo -e 'vm.dirty_background_bytes = 4194304\nvm.dirty_bytes = 4194304' | sudo tee /etc/sysctl.d/vm.conf >/dev/null 2>&1
    # systemd kill procress
    sudo sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=10s/g' /etc/systemd/system.conf >/dev/null 2>&1
    # network manager autoconnect
    echo -e '[connection]\nconnection.autoconnect-slaves=1' | sudo tee /etc/NetworkManager/NetworkManager.conf >/dev/null 2>&1
    echo -e "[Match]\nName=en*\nName=eth*\n[Network]\nDHCP=yes\nIPv6PrivacyExtensions=yes\n[DHCP]\nRouteMetric=512\n" | sudo tee /etc/systemd/network/20-ethernet.network >/dev/null 2>&1
    echo -e "[Match]\nName=wlp*\nName=wlan*\n\n[Network]\nDHCP=yes\nIPv6PrivacyExtensions=yes\n\n[DHCP]\nRouteMetric=1024\n" | sudo tee /etc/systemd/network/20-wireless.network >/dev/null 2>&1

    # disable gnome keyring to speedup sddm
    sudo sed -i -e '/^[^#]/ s/\(^.*pam_gnome_keyring.*$\)/#\1/' /etc/pam.d/sddm
    sudo sed -i -e '/^[^#]/ s/\(^.*pam_gnome_keyring.*$\)/#\1/' /etc/pam.d/sddm-autologin
    # disable kwallet keyring to speedup sddm
    sudo sed -i -e '/^[^#]/ s/\(^.*pam_kwallet5.*$\)/#\1/' /etc/pam.d/sddm
    sudo sed -i -e '/^[^#]/ s/\(^.*pam_kwallet5.*$\)/#\1/' /etc/pam.d/sddm-autologin
    # release config
    echo -e "[General]\nName=KOOMPI OS\nPRETTY_NAME=KOOMPI OS\nLogoPath=/usr/share/icons/koompi/koompi.svg\nWebsite=http://www.koompi.com\nVersion=2.6.0\nVariant=Rolling Release\nUseOSReleaseVersion=false" | sudo tee /etc/xdg/kcm-about-distrorc >/dev/null 2>&1
    echo -e 'NAME="KOOMPI OS"\nPRETTY_NAME="KOOMPI OS"\nID=koompi\nBUILD_ID=rolling\nANSI_COLOR="38;2;23;147;209"\nHOME_URL="https://www.koompi.com/"\nDOCUMENTATION_URL="https://wiki.koompi.org/"\nSUPPORT_URL="https://t.me/koompi"\nBUG_REPORT_URL="https://t.me/koompi"\nLOGO=/usr/share/icons/koompi/koompi.svg' | sudo tee /etc/os-release >/dev/null 2>&1
    # nano config
    grep "include /usr/share/nano-syntax-highlighting/*.nanorc" /etc/nanorc >/dev/null 2>&1
    [[ $? -eq 1 ]] && echo -e "include /usr/share/nano-syntax-highlighting/*.nanorc" | sudo tee -a /etc/nanorc >/dev/null 2>&1
    # hostname
    echo "koompi_os" | sudo tee /etc/hostname >/dev/null 2>&1
    # reflector
    sudo systemctl enable reflector.service >/dev/null 2>&1
    echo -e '--save /etc/pacman.d/mirrorlist \n--country "Hong Kong" \n--country Singapore \n--country Japan \n--country China \n--latest 20 \n--protocol https --sort rate' | sudo tee /etc/xdg/reflector/reflector.conf >/dev/null 2>&1

    PRODUCT=$(cat /sys/class/dmi/id/product_name)

    if [[ ${PRODUCT} == "KOOMPI E11" ]]; then
        smart_install rtl8723bu-git-dkms >/dev/null 2>&1
    fi

    sudo systemctl enable --now systemd-timedated systemd-timesyncd >/dev/null 2>&1
    sudo timedatectl set-local-rtc 0 >/dev/null 2>&1
    sudo timedatectl set-ntp 1 >/dev/null 2>&1
    sudo hwclock --systohc --localtime >/dev/null 2>&1

    # Add to pix group for pix
    groups | grep "pix" >/dev/null 2>&1
    if [[ $? -eq 1 ]]; then
        sudo groupadd pix >/dev/null 2>&1
        sudo usermod -a -G pix $USER >/dev/null 2>&1
        sudo chgrp -R pix /var/lib/pix >/dev/null 2>&1
        sudo chmod -R 2775 /var/lib/pix >/dev/null 2>&1
    fi
    # Add to input group for libinput gesture
    groups | grep "input" >/dev/null 2>&1
    if [[ $? -eq 1 ]]; then
        sudo usermod -a -G input $USER >/dev/null 2>&1
    fi
}

function install_upgrade() {
    sudo rm -rf /etc/skel

    smart_install \
        koompi-wallpapers \
        koompi-plasma-themes \
        sddm-theme-koompi \
        qogir-icon-theme-koompi \
        qogir-theme-koompi \
        la-capitaine-icon-theme-koompi \
        mcmojave-kde-theme-koompi \
        mcmojave-cursors-git \
        kwin-decoration-sierra-breeze-enhanced-git \
        fluent-decoration-git \
        kvantum-qt5 \
        kvantum-theme-fluent-git \
        koompi-theme-manager-qt5 \
        latte-dock \
        koompi-pacman-hooks \
        pi \
        pix \
        koompi-skel \
        pacman-contrib \
        linux \
        linux-headers \
        linux-firmware \
        intel-ucode \
        amd-ucode \
        acpi \
        acpi_call-dkms \
        dkms \
        sddm \
        sddm-kcm \
        libinput \
        xf86-input-libinput \
        xorg-xinput \
        libinput-gestures \
        libinput_gestures_qt \
        xdotool \
        kwin-scripts-parachute \
        kwin-scripts-sticky-window-snapping-git \
        fcitx5 \
        fcitx5-configtool \
        fcitx5-gtk \
        fcitx5-qt \
        fcitx5-chewing \
        fcitx5-chinese-addons \
        fcitx5-hangul \
        fcitx5-anthy \
        fcitx5-material-color \
        fcitx5-table-extra \
        fcitx5-table-other \
        ttf-khmer \
        inter-font \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        dolphin \
        kio \
        kio-extras \
        kio-fuse \
        kio-gdrive \
        audiocd-kio \
        kdegraphics-thumbnailers \
        konsole \
        nano \
        nano-syntax-highlighting \
        vim \
        kate \
        visual-studio-code-bin \
        firefox \
        google-chrome \
        telegram-desktop \
        teams \
        zoom \
        xdman \
        libreoffice-fresh \
        libreoffice-fresh-km \
        kcalc \
        okular \
        spectacle \
        freemind \
        gimp \
        inkscape \
        krita \
        darktable \
        gwenview \
        vlc \
        kdenlive \
        handbrake \
        obs-studio \
        webcamoid-git \
        libuvc \
        akvcam-dkms-git \
        elisa \
        pulseaudio \
        pulseaudio-alsa \
        pulseaudio-bluetooth \
        ark \
        zip \
        unzip \
        unrar \
        p7zip \
        partitionmanager \
        filelight \
        kdf \
        anydesk \
        knewstuff \
        kitemmodels \
        kdeclarative \
        qt5-graphicaleffects \
        appstream-qt \
        archlinux-appstream-data \
        hicolor-icon-theme \
        kirigami2 \
        discount \
        kuserfeedback \
        packagekit-qt5 \
        cups \
        libcups \
        cups-pdf \
        cups-filters \
        cups-pk-helper \
        foomatic-db-engine \
        foomatic-db \
        foomatic-db-ppds \
        foomatic-db-nonfree \
        foomatic-db-nonfree-ppds \
        gutenprint \
        foomatic-db-gutenprint-ppds \
        libpaper \
        system-config-printer \
        nss-mdns \
        hplip \
        a2ps \
        archlinux-keyring \
        zstd \
        bash-completion \
        ntp

}

function apply_new_theme() {

    cp -rf /etc/skel/.bash_aliases ${HOME} >/dev/null 2>&1
    cp -rf /etc/skel/.bash_history ${HOME} >/dev/null 2>&1
    cp -rf /etc/skel/.bash_profile ${HOME} >/dev/null 2>&1
    cp -rf /etc/skel/.bashrc ${HOME} >/dev/null 2>&1
    cp -rf /etc/skel/.bash_script ${HOME} >/dev/null 2>&1
    cp -rf /etc/skel/.config ${HOME} >/dev/null 2>&1
    mkdir -p /etc/sddm.conf.d/
    echo -e "[Autologin]\nRelogin=false\nSession=\nUser=\n\n[General]\nHaltCommand=/usr/bin/systemctl poweroff\nRebootCommand=/usr/bin/systemctl reboot\n\n[Theme]\nCurrent=koompi-dark\n\n[Users]\nMaximumUid=60000\nMinimumUid=1000\n" | sudo tee /etc/sddm.conf.d/kde_settings.conf >/dev/null 2>&1
    sh /usr/share/org.koompi.theme.manager/kmp-dark.sh >/dev/null 2>&1
}

function update_grub() {
    [[ -f /etc/default/grub ]] && sudo rm -rf /etc/default/grub
    smart_install grub-silent

    sudo sed -i -e 's/GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="KOOMPI_OS"/g' /etc/default/grub
    # kernel

    sudo sed -i -e "s/HOOKS=\"base udev.*/HOOKS=\"base systemd fsck autodetect modconf block keyboard keymap filesystems\"/g" /etc/mkinitcpio.conf
    sudo sed -i -e "s/HOOKS=(base udev.*/HOOKS=\"base systemd fsck autodetect modconf block keyboard keymap filesystems\"/g" /etc/mkinitcpio.conf
    sudo mkinitcpio -p linux >/dev/null 2>&1
    grep "StandardOutput=null" /etc/systemd/system/systemd-fsck-root.service >/dev/null 2>&1
    if [[ $? == 1 ]]; then
        echo -e "\nStandardOutput=null\nStandardError=journal+console\n" | sudo EDITOR='tee -a' systemctl edit --full systemd-fsck-root.service >/dev/null 2>&1
        echo -e "\nStandardOutput=null\nStandardError=journal+console\n" | sudo EDITOR='tee -a' systemctl edit --full systemd-fsck@.service >/dev/null 2>&1
    fi

    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
}

function prevent_power_management() {
    sudo systemctl --quiet --runtime mask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
}

function allow_power_management() {
    sudo systemctl --quiet --runtime unmask halt.target poweroff.target reboot.target kexec.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target sleep.target >/dev/null 2>&1
}

sudo -v
echo -e "${CYAN}====================================================================== ${NC}"
echo -e "${CYAN} ██╗  ██╗ ██████╗  ██████╗ ███╗   ███╗██████╗ ██╗     ██████╗ ███████╗ ${NC}"
echo -e "${CYAN} ██║ ██╔╝██╔═══██╗██╔═══██╗████╗ ████║██╔══██╗██║    ██╔═══██╗██╔════╝ ${NC}"
echo -e "${CYAN} █████╔╝ ██║   ██║██║   ██║██╔████╔██║██████╔╝██║    ██║   ██║███████╗ ${NC}"
echo -e "${CYAN} ██╔═██╗ ██║   ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██║    ██║   ██║╚════██║ ${NC}"
echo -e "${CYAN} ██║  ██╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ██║    ╚██████╔╝███████║ ${NC}"
echo -e "${CYAN} ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝     ╚═════╝ ╚══════╝ ${NC}"
echo -e "${CYAN}====================================================================== ${NC}"
echo -e ""
echo -e "Upgrade to version 2.6.0"
echo -e "Initialzing generation upgrade"
echo -e ""
prevent_power_management
echo -e "${RED}NOTE: During update, do not turn off your computer.${NC}"
echo -e ""

if [[ $continues -eq 1 ]]; then
    (insert_koompi_repo) &
    spinner "Updating the new repository of KOOMPI OS"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (remove_orphans) &
    spinner "Cleaning up unneed packages"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (refresh_mirror) &
    spinner "Ranking mirror repositories"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (security_patch) &
    spinner "Updating the default security configurations"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (smart_update) &
    spinner "Updating all installed applications"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (install_upgrade) &
    spinner "Upgrading to KOOMPI OS 2.6.0"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (update_grub) &
    spinner "Updating bootloader"
    completed=$((completed + 1))
fi

if [[ $continues -eq 1 ]]; then
    (apply_new_theme) &
    spinner "Applying generation upgrade"
    completed=$((completed + 1))
fi
if [[ $continues -eq 1 ]]; then
    echo -e ""
    allow_power_management
    echo -e "${CYAN}====================================================================== ${NC}"
    echo -e ""
    echo -e "${GREEN}Upgraded to version 2.6.0${NC}"
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
