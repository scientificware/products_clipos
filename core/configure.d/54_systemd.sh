#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2017 ANSSI. All rights reserved.

# Safety settings: do not remove!
set -o errexit -o nounset -o pipefail

# The prelude to every script for this SDK. Do not remove it.
source /mnt/products/${COSMK_SDK_PRODUCT}/${COSMK_SDK_RECIPE}/prelude.sh

# Set symlinks for hostname & machine-id
ln -sf "/mnt/state/core/etc/hostname"   "${CURRENT_OUT_ROOT}/etc/hostname"
ln -sf "/mnt/state/core/etc/machine-id" "${CURRENT_OUT_ROOT}/etc/machine-id"

sdk_info "Setup symlinks for firmware & modules profiles"
install -o 0 -g 0 -m 0755 -d "${CURRENT_OUT_ROOT}/etc/modules-load.d"
ln -sf "/mnt/state/core/etc/modules-load.d/hardware.conf" \
    "${CURRENT_OUT_ROOT}/etc/modules-load.d/hardware.conf"
ln -sf "/mnt/state/core/etc/firmware" "${CURRENT_OUT_ROOT}/lib64/firmware"

# Set systemd configuration
sdk_info "Set systemd configuration."
rm -rf "${CURRENT_OUT_ROOT}/etc/systemd/system"
install -o 0 -g 0 -m 0755 -d "${CURRENT_OUT_ROOT}/etc/systemd/system"
install -o 0 -g 0 -m 0755 -d "${CURRENT_OUT_ROOT}/etc/systemd/system/getty.target.wants"
install -o 0 -g 0 -m 0755 -d "${CURRENT_OUT_ROOT}/etc/systemd/system/multi-user.target.wants"
ln -s "/lib/systemd/system/getty@.service" \
    "${CURRENT_OUT_ROOT}/etc/systemd/system/getty.target.wants/getty@tty1.service"
ln -s "/lib/systemd/system/multi-user.target" \
    "${CURRENT_OUT_ROOT}/etc/systemd/system/default.target"

# Enable dbus-broker as system and user bus
systemctl --root="${CURRENT_OUT_ROOT}" enable dbus-broker
systemctl --root="${CURRENT_OUT_ROOT}" --global enable dbus-broker

# Mask unneeded systemd user instances
rm "${CURRENT_OUT_ROOT}/lib/systemd/system/user@.service"
ln -s '/dev/null' "${CURRENT_OUT_ROOT}/etc/systemd/system/user@.service"

# TODO: Fix /var/run symlink setup
sed -i "s|L /var/run - - - - ../run|L /var/run - - - - /run|" "${CURRENT_OUT_ROOT}/usr/lib/tmpfiles.d/var.conf"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
