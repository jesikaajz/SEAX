#! /bin/bash
export BORG_PASSPHRASE="seax2025"
/usr/bin/borg create --stats --progress ~/backup/backup-borg::auto-$(date +%Y-%m-%d) /root
