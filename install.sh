#! /bin/bash
set -euo pipefail

# Uses GNU Stow to install local files as necessary
stow -d installable -t /etc/systemd/system systemd

systemctl daemon-reload
