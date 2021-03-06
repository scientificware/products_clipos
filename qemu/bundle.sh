#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2017 ANSSI. All rights reserved.

# Safety settings: do not remove!
set -o errexit -o nounset -o pipefail

# The prelude to every script for this SDK. Do not remove it.
source /mnt/products/${COSMK_SDK_PRODUCT}/${COSMK_SDK_RECIPE}/prelude.sh

# Setup the minimal required layout for the state partition.
# This only includes files that must exist before the initramfs pivot_root or
# before the systemd-tmpfiles setup completes. Other state files should be
# setup using systemd-tmpfiles.

# This is required as long as we don't have installer support for QEMU images.
# This setup will be done by the installer for real hardware.

readonly CURRENT_STATE="${CURRENT_OUT}/qemu-state"
readonly CURRENT_RECIPE_D="/mnt/products/${COSMK_PRODUCT}/${COSMK_RECIPE}/bundle.d"
readonly CORE_OUT_ROOT="/mnt/out/${COSMK_PRODUCT}/${COSMK_PRODUCT_VERSION}/core/configure/root"

# We need to remove the state directory manually here as we use non root UIDs
# and GIDs which map to non-user owned UIDs/GIDs outside the user namespace for
# rootless podman.
rm -rf "${CURRENT_STATE}"
mkdir "${CURRENT_STATE}"

# hostname & machine-id
readonly PRODUCT_NAME="${COSMK_PRODUCT_SHORT_NAME}"
install -o 0 -g 0 -m 0755 -d "${CURRENT_STATE}/core/etc"
echo "${PRODUCT_NAME}-qemu" > "${CURRENT_STATE}/core/etc/hostname"
echo "${PRODUCT_NAME}-qemu" | md5sum | awk '{print $1}' > "${CURRENT_STATE}/core/etc/machine-id"

# /var/log/journal
# systemd-journal GID must match the one set in core/configure rootfs
journald_gid="$(grep "systemd-journal:" "${CORE_OUT_ROOT}/etc/group" | cut -d: -f 3)"
install -o 0 -g "${journald_gid}" -m 2755 -d "${CURRENT_STATE}/core/var/log/journal"

sdk_info "Setting up modules and firmwares"
readonly PROFILES_DIR="/usr/share/hardware/profiles/kvm_ovmf64"
install -o 0 -g 0 -m 0755 -d "${CURRENT_STATE}/core/etc/modules-load.d"
ln -sf "${PROFILES_DIR}/modules" "${CURRENT_STATE}/core/etc/modules-load.d/hardware.conf"
ln -sf "${PROFILES_DIR}/firmware" "${CURRENT_STATE}/core/etc/firmware"

# Network setup
install -o 0 -g 0 -m 0755 -d "${CURRENT_STATE}/core/etc/systemd/network"
install -o 0 -g 0 -m 0644 \
    "${CURRENT_RECIPE_D}/network/10-wired.network"\
    "${CURRENT_STATE}/core/etc/systemd/network/10-wired.network"

# Make the /etc/resolv.conf symlink point to a valid (empty) file:
install -o 0 -g 0 -m 0644 /dev/null "${CURRENT_STATE}/core/etc/resolv.conf"

# Setup admin & audit home dirs
admin_id="$(grep "admin:" "${CORE_OUT_ROOT}/etc/passwd" | cut -d: -f 3)"
audit_id="$(grep "audit:" "${CORE_OUT_ROOT}/etc/passwd" | cut -d: -f 3)"
install -o 0 -g 0 -m 0755 -d "${CURRENT_STATE}/core/home"
install -o ${admin_id} -g ${admin_id} -m 0700 -d "${CURRENT_STATE}/core/home/admin"
install -o ${audit_id} -g ${audit_id} -m 0700 -d "${CURRENT_STATE}/core/home/audit"
if is_instrumentation_feature_enabled "passwordless-root-login"; then
    install -o 0 -g 0 -m 0700 -d "${CURRENT_STATE}/core/home/root"
fi

# Add SSH keys for audit & admin
for key in "${CURRENT_CACHE}/ssh_admin" "${CURRENT_CACHE}/ssh_audit" "${CURRENT_CACHE}/ssh_root"; do
    if [[ ! -f "${key}" ]]; then
        ssh-keygen -t ecdsa -f "${key}" -N ""
    fi
done

install -o ${admin_id} -g ${admin_id} -m 0700 -d "${CURRENT_STATE}/core/home/admin/.ssh"
install -o ${admin_id} -g ${admin_id} -m 0700 -D \
    "${CURRENT_CACHE}/ssh_admin.pub" \
    "${CURRENT_STATE}/core/home/admin/.ssh/authorized_keys"

install -o ${audit_id} -g ${audit_id} -m 0700 -d "${CURRENT_STATE}/core/home/audit/.ssh"
install -o ${audit_id} -g ${audit_id} -m 0700 -D \
    "${CURRENT_CACHE}/ssh_audit.pub" \
    "${CURRENT_STATE}/core/home/audit/.ssh/authorized_keys"

if is_instrumentation_feature_enabled "allow-ssh-root-login"; then
    install -o 0 -g 0 -m 0700 -d "${CURRENT_STATE}/core/home/root/.ssh"
    install -o 0 -g 0 -m 0700 -D \
        "${CURRENT_CACHE}/ssh_root.pub" \
        "${CURRENT_STATE}/core/home/root/.ssh/authorized_keys"
fi

# Setup /etc/ssh/host_keys
install -o 0 -g 0 -m 0700 -d "${CURRENT_STATE}/core/etc/ssh/host_keys/"
if [[ ! -f "${CURRENT_CACHE}/host_key" ]]; then
    ssh-keygen -t ecdsa-sha2-nistp256 -f "${CURRENT_CACHE}/host_key" -N ""
fi
install -o 0 -g 0 -m 0600 "${CURRENT_CACHE}/host_key"     "${CURRENT_STATE}/core/etc/ssh/host_keys/ecdsa_key"
install -o 0 -g 0 -m 0600 "${CURRENT_CACHE}/host_key.pub" "${CURRENT_STATE}/core/etc/ssh/host_keys/ecdsa_key.pub"

sdk_info "Customizing the IPsec stack..."

# Retreive ipsec GID
ipsec_gid="$(grep "ipsec:" "${CORE_OUT_ROOT}/etc/group" | cut -d: -f 3)"
# Dummy PKI for the testbed IPsec infrastructure:
readonly ipsec_pki_path="${CURRENT_RECIPE_D}/pki"
install -o ${admin_id} -g ${ipsec_gid} -m 0750 -d \
    "${CURRENT_STATE}/core/etc/swanctl/x509"{,ca} \
    "${CURRENT_STATE}/core/etc/swanctl/private"
install -o ${admin_id} -g ${ipsec_gid} -m 0640 \
    "${ipsec_pki_path}/root-ca.cert.pem" \
    "${CURRENT_STATE}/core/etc/swanctl/x509ca/root-ca.cert.pem"
install -o ${admin_id} -g ${ipsec_gid} -m 0640 \
    "${ipsec_pki_path}/client.cert.pem" \
    "${CURRENT_STATE}/core/etc/swanctl/x509/client.cert.pem"
install -o ${admin_id} -g ${ipsec_gid} -m 0640 \
    "${ipsec_pki_path}/client.key.pem" \
    "${CURRENT_STATE}/core/etc/swanctl/private/client.key.pem"
# strongSwan configuration
readonly ipsec_configuration="${CURRENT_RECIPE_D}/strongswan"
install -o ${admin_id} -g ${ipsec_gid} -m 0750 -d "${CURRENT_STATE}/core/etc/swanctl/conf.d"
install -o ${admin_id} -g ${ipsec_gid} -m 0640 \
    "${ipsec_configuration}/office_net.conf" \
    "${CURRENT_STATE}/core/etc/swanctl/conf.d/office_net.conf"
# Replace placeholders by using a subshell as the function
# `replace_placeholders` uses the exported environment variables as input for
# the placeholders to replace. This subshell enables us not to mess with the
# environment variables of this whole script.
(
    export OFFICENET_LOCAL_CERTS="client.cert.pem"
    export OFFICENET_REMOTE_ADDRS="172.27.1.10"
    export OFFICENET_REMOTE_CACERTS="root-ca.cert.pem"
    export OFFICENET_REMOTE_ID="ipsec-server.dummy.clip-os.org"
    export OFFICENET_LOCAL_TS="172.27.100.100/32"
    export OFFICENET_REMOTE_TS="0.0.0.0/0"
    replace_placeholders "${CURRENT_STATE}/core/etc/swanctl/conf.d/office_net.conf"
)

sdk_info "Installing updater configuration to test updates..."
# Install updater remote configuration
readonly updater_config="${CURRENT_RECIPE_D}/updater"
install -o ${admin_id} -g 0 -m 0750 -d "${CURRENT_STATE}/core/etc/updater"
for f in "remote.toml" "rootca.pem"; do
    install -o ${admin_id} -g 0 -m 0640 \
        "${updater_config}/${f}" \
        "${CURRENT_STATE}/core/etc/updater/${f}"
done

sdk_info "Installing default nftables rules..."
# Install nftables rules
install -o 0 -g ${admin_id} -m 750 -d "${CURRENT_STATE}/core/etc/nftables"
install -o 0 -g ${admin_id} -m 640 \
    "${CURRENT_RECIPE_D}/nft/rules.nft" \
    "${CURRENT_STATE}/core/etc/nftables/rules.nft"
install -o 0 -g ${admin_id} -m 640 \
    "${CURRENT_RECIPE_D}/nft/rules.ipsec0.nft" \
    "${CURRENT_STATE}/core/etc/nftables/rules.ipsec0.nft"

sdk_info "Installing secret keys for chrony..."
chrony_id="$(grep "chrony:" "${CORE_OUT_ROOT}/etc/passwd" | cut -d: -f 3)"
install -o 0 -g ${chrony_id} -m 750 -d "${CURRENT_STATE}/core/etc/chrony"
install -o 0 -g ${chrony_id} -m 640 \
    "${CURRENT_RECIPE_D}/chronyd/chrony.keys" \
    "${CURRENT_STATE}/core/etc/chrony/chrony.keys"

# Install CLIP OS custom environment file to specify interface used to bind
# XFRM interface and private IP for IPsec traffic
# WARNING: This is subject to change before the 5.0 stable release.
install -o 0 -g ${admin_id} -m 750 -d "${CURRENT_STATE}/core/etc/clipos"
install -o 0 -g ${admin_id} -m 640 \
    "${CURRENT_RECIPE_D}/clipos/ipsec0.conf" \
    "${CURRENT_STATE}/core/etc/clipos/ipsec0.conf"

if is_instrumentation_feature_enabled "allow-ssh-root-login"; then
    # Enable SSH login from local network for development
    sed -i 's|#\s*\(tcp dport { 22 } accept$\)|\1|g' \
        "${CURRENT_STATE}/core/etc/nftables/rules.nft"
fi

# Touch a specific file to enable simple initramfs check.
touch "${CURRENT_STATE}/.setup-done"

sdk_info "Creating QEMU initial core state tarball..."
# Bundle the state folder content as a tarball while making sure to keep
# filesystem advanced properties such as sparse information or extended
# attributes:
tar --create --xattrs --sparse \
    --file "${CURRENT_OUT}/qemu-core-state.tar" \
    --directory "${CURRENT_STATE}" \
    .

# vim: set ts=4 sts=4 sw=4 et ft=sh:
