#!/bin/bash
grep "dev.koompi.org" /etc/pacman.conf >/dev/null 2>&1
[[ $? -eq 1 ]] && echo -e '\n[koompi]\nSigLevel = Never\nServer = https://dev.koompi.org/koompi\n' | sudo tee -a /etc/pacman.conf >/dev/null 2>&1
