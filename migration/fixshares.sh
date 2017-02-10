#!/bin/bash

#
# Copyright (C) 2017 Davide Principi <davide.principi@nethesis.it>
#
# This script is part of NethServer.
#
# NethServer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License,
# or any later version.
#
# NethServer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NethServer.  If not, see COPYING.
#

#
# This script iterates over all user maildirs and fixes shares and acl, by
# adding the @domain suffix to account identifiers.
#
# Three sed scripts are generated in /tmp. They map short to long names for the
# corresponding dovecot internal databases (which are plain text files):
#
#  1. ACL, for dovecot-acl files,
#  2. SHARED, for subscriptions files,
#  3. DB, for shared-mailboxes.db file
#

# exit on errors
set -e

TMP_REMAP_ACL=$(mktemp /tmp/fixshares-acl.XXXXXXXX)
TMP_REMAP_SHARED=$(mktemp /tmp/fixshares-shared.XXXXXXXX)
TMP_REMAP_DB=$(mktemp /tmp/fixshares-db.XXXXXXXX)

cleanup ()
{
    rm -f $TMP_REMAP_ACL $TMP_REMAP_SHARED $TMP_REMAP_DB
}

trap cleanup EXIT HUP TERM

cd /var/lib/nethserver/vmail

DB="shared-mailboxes.db"
DOMAIN=$(hostname -d)

if [[ ! -f $DB ]]; then
    echo "[ERROR] Missing $DB file"
    exit 1
fi

cp -f $DB ${DB}.bak

for ACCOUNT in *${DOMAIN}; do
    SHORT="${ACCOUNT%%@${DOMAIN}}"
    echo "[NOTICE] Map $SHORT to $ACCOUNT"
    echo "s:(user/|group/|anyone/)${SHORT}/:\1${ACCOUNT}/:g" >> $TMP_REMAP_DB
    echo "s:/${SHORT}\$:/${ACCOUNT}:g" >> $TMP_REMAP_DB
    echo "s:^user=${SHORT} :user=${ACCOUNT} :g" >> $TMP_REMAP_ACL
    echo "s:Shared/${SHORT}/:Shared/${ACCOUNT}/:g" >> $TMP_REMAP_SHARED
done

sed -i -r -f $TMP_REMAP_DB $DB

if ! grep -q "^shared/shared-boxes/anyone/vmail" $DB; then
    echo "[NOTICE] Share vmail with anyone"
    echo "shared/shared-boxes/anyone/vmail" >> $DB
    echo "1" >> $DB
fi

find . -name dovecot-acl -print0 | xargs -0 -- sed -i -r -f $TMP_REMAP_ACL
find . -name subscriptions -print0 | xargs -0 -- sed -i -r -f $TMP_REMAP_SHARED
