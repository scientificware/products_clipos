#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2017-2018 ANSSI. All rights reserved.

# Meta-script for the targets "build" step:

# Safety settings: do not remove!
set -o errexit -o nounset -o pipefail

# The prelude to every script for this SDK. Do not remove it.
source /mnt/products/${CURRENT_SDK_PRODUCT}/${CURRENT_SDK_RECIPE}/scripts/prelude.sh

if [[ "${#@}" -eq 0 ]]; then
    eerror "No packages to emerge (no arguments given)."
    exit 1
fi

# Needed to get EMERGE_BUILDROOTWITHBDEPS_OPTS:
source /mnt/products/${CURRENT_SDK_PRODUCT}/${CURRENT_SDK_RECIPE}/scripts/portage/emergeopts.sh

# This current meta-script works only on a detached root tree.
# Emerge, qlist and other Portage script will read this environment variable
# and will work in this ROOT tree.
export ROOT="${CURRENT_OUT_ROOT}"

einfo "Building baselayout in ROOT:"
emerge ${EMERGE_BUILDROOTWITHBDEPS_OPTS} sys-apps/baselayout

# Systematically remove previously built binary packages for meta ebuilds
for pkg in $@; do
    rm -fv /mnt/cache/${CURRENT_PRODUCT}/${CURRENT_PRODUCT_VERSION}/${CURRENT_RECIPE}/binpkgs/${pkg}*
done

einfo "Building the packages to emerge in ROOT:"
emerge ${EMERGE_BUILDROOTWITHBDEPS_OPTS} "$@"

# Extract the detailed list of installed packages in ROOT
qlist -IvSSRUC > "${CURRENT_OUT}/root.packages"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
