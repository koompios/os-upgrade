#!/bin/bash

function spinner() {
    local info="$1"
    local pid=$!
    local delay=0.5
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c] $info" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        local reset="\b\b\b\b\b\b"
        for ((i = 1; i <= $(echo $info | wc -c); i++)); do
            reset+="\b"
        done
        printf $reset
    done

    printf "[\xE2\x9C\x94]"
}

function refresh_mirror() {
    sudo pacman -Qi reflector >/dev/null 2>&1
    [[ $? == 1 ]] && sudo pacman -Sy --noconfirm --quiet reflector >/dev/null 2>&1
    sudo reflector --country "Hong Kong" --country Singapore --country Japan --country China --latest 20 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>&1
    sudo sed -i '/0x.sg/d' /etc/pacman.d/mirrorlist
}

function remove_orphans() {
    sudo pacman -Rs $(sudo pacman -Qqtd) --noconfirm --quiet >/dev/null 2>&1
}

function update_pacman_config() {
    sudo sed -i 's/Required[[:space:]]DatabaseOptional/Never/g' /etc/pacman.conf
}

function insert_koompi_repo() {
    grep "dev.koompi.org" /etc/pacman.conf >/dev/null 2>&1
    [[ $? == 1 ]] && echo -e '\n[koompi]\nSigLevel = Never\nServer = https://dev.koompi.org/koompi\n' | sudo tee -a /etc/pacman.conf >/dev/null 2>&1
}

function package_update() {
    sudo pacman -Syu --noconfirm --quiet >/dev/null 2>&1
}

function patch_sudo() {
    # Change passwrod timeout to 60 minutes
    echo -e 'Defaults timestamp_timeout=60' | sudo EDITOR='tee' visudo -f /etc/sudoers.d/timestamp_timeout >/dev/null 2>&1
    # Enable ***** sudo feedback
    echo -e 'Defaults pwfeedback' | sudo EDITOR='tee' visudo -f /etc/sudoers.d/pwfeedback >/dev/null 2>&1
    # Enable group wheel
    echo -e '%wheel ALL=(ALL) ALL' | sudo EDITOR='tee' visudo -f /etc/sudoers.d/10-installer >/dev/null 2>&1
}

function safe_install() {
    # prevent stale becuase of db lock
    [[ -f "/var/lib/pacman/db.lck" ]] && sudo rm -rf /var/lib/pacman/db.lck

    yes | sudo pacman -Syy --needed $@ >/dev/null 2>&1 >/tmp/installation.log
    if [[ $? == 1 ]]; then
        conflict_files=$(cat /tmp/installation.log | grep "exists in filesystem" | grep -o '/[^ ]*')
        if [[ ${#conflict_files[@]} -gt 0 ]]; then
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                [[ -f ${conflict_files[$i]} ]] && sudo rm -rf ${conflict_files[$i]}
            done
        fi
        safe_install $@
    fi
}

function install_themes() {
    safe_install \
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
        koompi-theme-manager-qt5 latte-dock
}

sudo -v
echo -e "====================================================================== "
echo -e " ██╗  ██╗ ██████╗  ██████╗ ███╗   ███╗██████╗ ██╗     ██████╗ ███████╗ "
echo -e " ██║ ██╔╝██╔═══██╗██╔═══██╗████╗ ████║██╔══██╗██║    ██╔═══██╗██╔════╝ "
echo -e " █████╔╝ ██║   ██║██║   ██║██╔████╔██║██████╔╝██║    ██║   ██║███████╗ "
echo -e " ██╔═██╗ ██║   ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██║    ██║   ██║╚════██║ "
echo -e " ██║  ██╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ██║    ╚██████╔╝███████║ "
echo -e " ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝     ╚═════╝ ╚══════╝ "
echo -e "====================================================================== "
echo -e "Version: 2.6.0"
echo -e "Prepareing for updates..."

# (refresh_mirror) &
# spinner "Refreshing mirrors..."
# echo -e ""
(remove_orphans) &
spinner "Remove orphans packages..."
echo -e ""
(insert_koompi_repo) &
spinner "Inserting KOOMPI repository"
echo -e ""
(update_pacman_config) &
spinner "Pathcing pacman config"
echo -e ""
(patch_sudo) &
spinner "Pacthing sudo config"
echo -e ""
(package_update) &
spinner "Updating applications..."
echo -e ""
(install_themes) &
spinner "Installing new applications..."
echo -e ""

echo -e "====================================================================== "
echo -e "Upgraded to version 2.6.0"
echo -e "Please restart your computer before continue using."
