#!/bin/bash

function spinner() {
    local info="$1"
    local pid=$!
    local delay=0.75
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
    # printf "\b\b\b\b"
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

function package_update() {
    sudo pacman -Syu --noconfirm --quiet >/dev/null 2>&1
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

(refresh_mirror) &
spinner "Refreshing mirrors..."
echo -e ""
(remove_orphans) &
spinner "Remove orphans packages..."
echo -e ""
(package_update) &
spinner "Updating applications..."
echo -e ""
