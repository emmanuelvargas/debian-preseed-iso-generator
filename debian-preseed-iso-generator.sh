#!/usr/bin/env bash
# This script generates Debian ISOs with preseed for multiple environments

set -e  # Exit on error
#set -u  # Treat unset variables as errors
set -o pipefail  # Fail if a piped command fails

# Define constants
readonly ISOFILEDIR="isofiles"
readonly NETINSTISO="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/"
readonly CHECKSUM="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"

function usage() {
  if [ "${1-0}" -ne 0 ]; then
    exec >&2
  fi
  printf "Usage: %s -n server_name -i ip_address/cidr -g gateway -d dns_ip\n" "$(basename "$0")"
  printf "\n"
  printf "  -n server_name\n"
  printf "      Name of the server to install\n"
  printf "  -i ip_address/cidr\n"
  printf "      IP address of the server to install on format ip/cidr (ex: 192.168.0.200/24)\n"
  printf "  -g gateway\n"
  printf "      network gateway\n"
  printf "  -d dns_ip\n"
  printf "      DNS Ip address\n"
  if [ "${1:-0}" -ge "0" ]; then
    exit "${1:-0}"
  fi
}

valid_ipv4() {
    local ip="${1}"
    [[ "${ip}" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]
    return "$?"
}

valid_cidr() {
    local ip_cidr="${1}"
    local status=1
    if [[ "${ip_cidr}" =~ ^[^/]*/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
        ip=$(echo "${ip_cidr}" | cut -d '/' -f 1)
        valid_ipv4 "${ip}" && status=0
    fi 
    return "${status}"
}

bin2ip() {
    local binary_sequence="${1}"
    echo "obase=10; ibase=2; ${binary_sequence}" | bc | xargs | tr ' ' '.'
}

cidr2netmask() {
    local ip_cidr="${1}"
    valid_cidr "${ip_cidr}" || return 1
    netmask_length="$(echo "${ip_cidr}" | cut -d '/' -f 2)"
    host_length="$((32-netmask_length))"
    ones="$(head -c "${netmask_length}" /dev/zero | tr '\0' '1')"
    zeros="$(head -c "${host_length}" /dev/zero | tr '\0' '0')"
    sequence="$(sed -E 's/(.{8})(.{8})(.{8})(.{8})/\1;\2;\3;\4/' <<< "${ones}${zeros}")"
    bin2ip "${sequence}"
}

# Ensure necessary commands are available
for cmd in wget curl sha256sum awk grep 7z gunzip gzip cpio genisoimage isohybrid; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required tool '$cmd' is not installed!"
        exit 1
    fi
done

while getopts "hn:i:g:d:" arg; do
  case $arg in
  h) usage ;;
  n) SRVNAME="${OPTARG}" ;;
  i) SRVNET_IPCIDR="${OPTARG}" ;;
  g) SRVNET_GW="${OPTARG}" ;;
  d) SRVNET_DNS="${OPTARG}" ;;
  *) usage 1 ;;
  esac
done

if [ ! "$SRVNAME" ] || [ ! "$SRVNET_IPCIDR" ] || [ ! "$SRVNET_GW" ] || [ ! "$SRVNET_DNS" ]; then
  echo "arguments -n -i -g -d must be provided"
  usage -1 
  exit 1
fi

if ! valid_cidr "${SRVNET_IPCIDR}"; then
  echo "${SRVNET_IPCIDR} is not a valid CIDR"
  usage -1
  exit 1
fi

SRVNET_IP="$(echo "${SRVNET_IPCIDR}" | cut -d '/' -f 1)"
SRVNET_MASK=$(cidr2netmask "${SRVNET_IPCIDR}")
echo -e "SRVNET_IP=${SRVNET_IP}\nSRVNET_MASK=${SRVNET_MASK}\n"

#exit 0

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
cp ../../preseed.cfg ../../preseed.cfg.tmp
sed -i "s/SRVNET_IP/${SRVNET_IP}/g; s/SRVNET_MASK/${SRVNET_MASK}/g; s/SRVNET_GW/${SRVNET_GW}/g; s/SRVNET_DNS/${SRVNET_DNS}/g; s/SRVNAME/${SRVNAME}/g" ../../preseed.cfg
echo ../../preseed.cfg | cpio --format=newc --create --append --file="${ISOFILEDIR}/install.amd/initrd"
cp ../../preseed.cfg.tmp ../../preseed.cfg

# add static files to cdrom
STATIC="./cdrom"
install -d -m 755 "${ISOFILEDIR}/preseed"
(
    cd "../../cdrom"
    find . -name \* -a ! \( -name \*~ -o -name \*.bak -o -name \*.orig \) -print0
) | cpio -v -p -L -0 -D "../../${STATIC}" "${ISOFILEDIR}/preseed"
chmod -w -R "${ISOFILEDIR}/preseed"

# replace grub boot options
chmod +w "${ISOFILEDIR}/boot/grub/grub.cfg"
cat "../../Files/grub.cfg" > "${ISOFILEDIR}/boot/grub/grub.cfg" 
chmod -w "${ISOFILEDIR}/boot/grub/grub.cfg"

# Add theme
(
    cd "../../Files/theme"
    find . -name \* -a ! \( -name \*~ -o -name \*.bak -o -name \*.orig \) -print0
) | cpio -v -p -L -0 -D "../../Files/theme" "${ISOFILEDIR}/boot/grub/theme/"

gzip "${ISOFILEDIR}/install.amd/initrd"
chmod --recursive -w "${ISOFILEDIR}/install.amd/"

# Generate new md5sum.txt
pushd "${ISOFILEDIR}" > /dev/null
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
popd > /dev/null

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
#sudo rm --recursive --force "${ISOFILEDIR}"
#sudo rm ../../preseed.cfg.tmp

popd > /dev/null