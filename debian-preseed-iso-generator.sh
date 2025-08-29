#!/usr/bin/env bash
# This script generates Debian ISOs with preseed for multiple environments

set -e  # Exit on error
set -u  # Treat unset variables as errors
set -o pipefail  # Fail if a piped command fails

# Define constants
readonly ISOFILEDIR="isofiles"
readonly NETINSTISO="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/"
readonly CHECKSUM="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"
readonly SRVNAME="pve03"
readonly SRVNET_IP="192.168.0.203"
readonly SRVNET_MASK="255.255.255.0"
readonly SRVNET_GW="192.168.0.254"
readonly SRVNET_DNS="192.168.0.103"


# Ensure necessary commands are available
for cmd in wget curl sha256sum awk grep 7z gunzip gzip cpio genisoimage isohybrid; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required tool '$cmd' is not installed!"
        exit 1
    fi
done

# Change to the script directory
BASEDIR=$(dirname "$0")
pushd "${BASEDIR}" > /dev/null || exit 1

# Find the latest Debian netinstall ISO filename
ISO_FILENAME=$(curl --silent "${NETINSTISO}" | grep -o 'debian-[^ ]*-amd64-netinst.iso' | head -n 1)
if [[ -z "ISOs/$ISO_FILENAME" ]]; then
    echo "Error: Could not determine the latest Debian netinstall ISO filename."
    exit 1
fi

# Check if an ISO file already exists and verify checksum
ISO_FILE=$(find . -maxdepth 2 -name "$ISO_FILENAME" -print -quit)
if [[ -n "${ISO_FILE}" ]]; then
    echo "Existing ISO found. Verifying checksum..."
    EXPECTED_CHECKSUM=$(curl --silent "${CHECKSUM}" | grep "$ISO_FILENAME" | awk '{print $1}')

    if [[ -z "${EXPECTED_CHECKSUM}" ]]; then
        echo "Error: No matching checksum entry found for ${ISO_FILE}."
        exit 1
    fi

    LOCAL_CHECKSUM=$(sha256sum "${ISO_FILE}" | awk '{print $1}')
    if [[ "${EXPECTED_CHECKSUM}" == "${LOCAL_CHECKSUM}" ]]; then
        echo "Checksum matches. No need to download a new ISO."
    else
        echo "Checksum mismatch! Downloading a new ISO..."
        rm --verbose --force "${ISO_FILE}"
        ISO_FILE=""
    fi
fi

# Download ISO if not present or checksum mismatch
if [[ -z "${ISO_FILE}" ]]; then
    echo "Downloading latest Debian netinstall ISO: ${ISO_FILENAME}"
    wget --no-parent --show-progress --directory-prefix="./ISOs" \
         "${NETINSTISO}${ISO_FILENAME}"

    ISO_FILE=$(find . -maxdepth 2 -name "$ISO_FILENAME" -print -quit)

    # Verify checksum of the downloaded ISO
    echo "Verifying downloaded ISO checksum..."
    EXPECTED_CHECKSUM=$(curl --silent "${CHECKSUM}" | grep "$ISO_FILENAME" | awk '{print $1}')
    if [[ -z "${EXPECTED_CHECKSUM}" ]]; then
        echo "Error: No matching checksum entry found for ${ISO_FILE}."
        exit 1
    fi
    LOCAL_CHECKSUM=$(sha256sum "${ISO_FILE}" | awk '{print $1}')
    if [[ "${EXPECTED_CHECKSUM}" != "${LOCAL_CHECKSUM}" ]]; then
        echo "Abort: Incorrect ISO downloaded."
        exit 1
    fi
fi

ISOFILE="${SRVNAME}-preseed-debian-netinst.iso"

if [[ ! -d "ISOs/${SRVNAME}" ]]; then
		mkdir -p ISOs/${SRVNAME}
fi

pushd "ISOs/${SRVNAME}" > /dev/null || exit 1

sudo rm --recursive --force "${ISOFILEDIR}"
sudo rm --force "${ISOFILE}"

# Extract ISO contents
7z x "../../${ISO_FILE}" -o"${ISOFILEDIR}"

# Modify initrd with preseed.cfg
chmod --recursive +w "${ISOFILEDIR}/install.amd/"
gunzip "${ISOFILEDIR}/install.amd/initrd.gz"
# TODO:
# put correct value in preseed file
cp ../../preseed.cfg ../../preseed.cfg.tmp
sed -i "s/SRVNET_IP/${SRVNET_IP}/g; s/SRVNET_MASK/${SRVNET_MASK}/g; s/SRVNET_GW/${SRVNET_GW}/g; s/SRVNET_DNS/${SRVNET_DNS}/g; s/SRVNAME/${SRVNAME}/g" ../../preseed.cfg
echo ../../preseed.cfg | cpio --format=newc --create --append --file="${ISOFILEDIR}/install.amd/initrd"
cp ../../preseed.cfg.tmp ../../preseed.cfg
gzip "${ISOFILEDIR}/install.amd/initrd"
chmod --recursive -w "${ISOFILEDIR}/install.amd/"

# Generate new md5sum.txt
pushd "${ISOFILEDIR}" > /dev/null
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
popd > /dev/null

# Create bootable ISO
# genisoimage -r -J -b isolinux/isolinux.bin -c isolinux/boot.cat --no-emul-boot \
# 						--boot-load-size 4 --boot-info-table -o "${ISOFILE}" "${ISOFILEDIR}"
# isohybrid "${ISOFILE}"

xorriso -as mkisofs -o "${ISOFILE}" -J -J -joliet-long -cache-inodes \
                        -c isolinux/boot.cat \
                        -b isolinux/isolinux.bin \
                        -no-emul-boot \
                        -boot-load-size 4 \
                        -boot-info-table \
                        -eltorito-alt-boot \
                        -e boot/grub/efi.img \
                        -no-emul-boot \
                        -isohybrid-gpt-basdat \
                        -isohybrid-apm-hfsplus "${ISOFILEDIR}"

# Clean up temporary directory
# sudo is needed because some of the files in the ISO tmp will not be deleted
sudo rm --recursive --force "${ISOFILEDIR}"
sudo rm ../../preseed.cfg.tmp

popd > /dev/null