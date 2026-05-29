#!/bin/bash
## kola:
##   tags: "needs-internet"
##   timeoutMin: 30
##   requiredTag: rebase-ociarchive
##   description: Minimal rebase to stable oci-archive to benchmark rpm-ostree rebase performance.

set -eux -o pipefail

# shellcheck disable=SC1091
. "$KOLA_EXT_DATA/commonlib.sh"

case "${AUTOPKGTEST_REBOOT_MARK:-}" in
"")
    # First boot: perform the rebase

    # Record the version we started at
    rpm-ostree status --json | jq -r '.deployments[0].version' > /srv/pre-rebase-version
    ok "Starting version: $(cat /srv/pre-rebase-version)"

    # If the marker file exists, set fsync=false in the ostree repo config
    if [ -f /etc/ostree-fsync-false ]; then
        echo "Setting fsync=false in ostree repo config"
        sudo ostree config --repo=/sysroot/ostree/repo set core.fsync false
        # Stop rpm-ostreed so cached config values are discarded;
        # it will be socket-activated fresh on the next rpm-ostree call.
        sudo systemctl stop rpm-ostreed.service
        ok "fsync=false configured and rpm-ostreed stopped"
    fi

    # # Copy the stable container image to a local oci-archive
    # echo "Pulling quay.io/fedora/fedora-coreos:stable to oci-archive..."
    # time skopeo copy --retry-times 3 --remove-signatures \
    #     docker://quay.io/fedora/fedora-coreos:stable \
    #     oci-archive:/srv/fcos-stable.ociarchive
    # ok "skopeo copy completed"

    # Download pre-built RHCOS oci-archive
    echo "Downloading RHCOS oci-archive..."
    time curl -L --retry 3 -o /srv/fcos-stable.ociarchive \
        https://dustymabe.fedorapeople.org/rhcos-9.6.20260401-0-ostree.x86_64.ociarchive
    ok "oci-archive download completed"

    # Perform the rebase
    echo "Rebasing to oci-archive..."
    time sudo rpm-ostree rebase \
        ostree-unverified-image:oci-archive:/srv/fcos-stable.ociarchive
    ok "rpm-ostree rebase completed"

    # Clean up the archive before rebooting to save disk space
    rm -f /srv/fcos-stable.ociarchive

    /tmp/autopkgtest-reboot rebase
    ;;

rebase)
    # Second boot: verify the rebase succeeded
    new_version=$(rpm-ostree status --json | jq -r '.deployments[0].version')
    old_version=$(cat /srv/pre-rebase-version)

    echo "Pre-rebase version: ${old_version}"
    echo "Post-rebase version: ${new_version}"

    if [ "${old_version}" == "${new_version}" ]; then
        fatal "Version did not change after rebase (still ${old_version})"
    fi

    ok "Rebase succeeded: ${old_version} -> ${new_version}"
    ;;

*) fatal "unexpected reboot mark: ${AUTOPKGTEST_REBOOT_MARK}";;
esac
