#!/bin/bash

function safe_install() {
    # prevent stale becuase db lock
    [[ -f "/var/lib/pacman/db.lck" ]] && sudo rm -rf /var/lib/pacman/db.lck

    yes | sudo pacman -Syy --needed $@ >/dev/null 2>&1 >err.txt
    if [[ $? == 1 ]]; then
        conflict_files=$(cat err.txt | grep "exists in filesystem" | grep -o '/[^ ]*')
        if [[ ${#conflict_files[@]} -gt 0 ]]; then
            for ((i = 0; i < ${#conflict_files[@]}; i++)); do
                [[ -f ${conflict_files[$i]} ]] && sudo rm -rf ${conflict_files[$i]}
            done
        fi
        safe_install $@
    fi
}

safe_install koompi-wallpapers koompi-plasma-themes sddm-theme-koompi qogir-icon-theme-koompi qogir-theme-koompi la-capitaine-icon-theme-koompi mcmojave-kde-theme-koompi mcmojave-cursors-git kwin-decoration-sierra-breeze-enhanced-git fluent-decoration-git kvantum-qt5 kvantum-theme-fluent-git koompi-theme-manager-qt5 latte-dock
