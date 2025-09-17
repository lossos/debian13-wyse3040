#!/usr/bin/env bash
set -euo pipefail

# Check for required commands
if ! command -v wget &> /dev/null; then
    echo "Error: 'wget' is not installed. Please add it to your build environment (e.g., Dockerfile)." >&2
    exit 1
fi

# ------------------------------------------------------------------
# Deb-conf variables that match the preseed
# ------------------------------------------------------------------
DEBIAN_VERSION="13.1.0"
ISO_URL="https://cdimage.debian.org/debian-cd/${DEBIAN_VERSION}/amd64/iso-cd/debian-${DEBIAN_VERSION}-amd64-netinst.iso"
ORIG_ISO="debian-${DEBIAN_VERSION}-amd64-netinst.iso"
WORK_DIR="/tmp/iso"
REMASTER="/tmp/remaster"

# ------------------------------------------------------------------
# 1. Download original netinst image (skip if already cached)
# ------------------------------------------------------------------
cd /build
[[ -f "${ORIG_ISO}" ]] || wget -q -O "${ORIG_ISO}" "${ISO_URL}"

# ------------------------------------------------------------------
# 2. Extract ISO content and initrd
# ------------------------------------------------------------------
rm -rf "${WORK_DIR}" "${REMASTER}"
mkdir -p "${WORK_DIR}" "${REMASTER}"

xorriso -osirrox on -indev "${ORIG_ISO}" -extract / "${WORK_DIR}"

# ------------------------------------------------------------------
# 2.5. Add custom udeb packages for F2FS support in the installer
# ------------------------------------------------------------------
echo "Adding custom F2FS udeb packages to the ISO..."
UDEB_TMP="/tmp/udebs"
rm -rf "${UDEB_TMP}"
mkdir -p "${UDEB_TMP}"
cd "${UDEB_TMP}" || { echo "Error: Failed to change directory to ${UDEB_TMP}"; exit 1; }

F2FS_TOOLS_UDEB_URL="http://ftp.debian.org/debian/pool/main/f/f2fs-tools/f2fs-tools-udeb_1.16.0-2_amd64.udeb"
# The kernel version for the installer might change. This is for the 13.1.0 netinst.
F2FS_MODULES_UDEB_URL="http://ftp.debian.org/debian/pool/main/l/linux-signed-amd64/f2fs-modules-6.12.43+deb13-amd64-di_6.12.43-1_amd64.udeb"

wget -q "${F2FS_TOOLS_UDEB_URL}" || { echo "Error: Failed to download f2fs-tools-udeb."; exit 1; }
wget -q "${F2FS_MODULES_UDEB_URL}" || { echo "Error: Failed to download f2fs-modules-udeb."; exit 1; }

# Create pool directories according to Debian archive structure
mkdir -p "${WORK_DIR}/pool/main/f/f2fs-tools"
mkdir -p "${WORK_DIR}/pool/main/l/linux-signed-amd64"

# Copy udebs to the correct pool directory
cp f2fs-tools-udeb_*.udeb "${WORK_DIR}/pool/main/f/f2fs-tools/"
cp f2fs-modules-*.udeb "${WORK_DIR}/pool/main/l/linux-signed-amd64/"

# Update the installer's package list to include the new udebs
PACKAGES_GZ="${WORK_DIR}/dists/trixie/main/debian-installer/binary-amd64/Packages.gz"
PACKAGES_FILE="${WORK_DIR}/dists/trixie/main/debian-installer/binary-amd64/Packages"

gunzip -c "${PACKAGES_GZ}" > "${PACKAGES_FILE}"

# Extract control info for f2fs-tools-udeb and patch the dependency
echo "" >> "${PACKAGES_FILE}"
dpkg-deb -I f2fs-tools-udeb_*.udeb control >> "${PACKAGES_FILE}"
echo "" >> "${PACKAGES_FILE}"
dpkg-deb -I f2fs-modules-*.udeb control >> "${PACKAGES_FILE}"
gzip -9c "${PACKAGES_FILE}" > "${PACKAGES_GZ}"
rm "${PACKAGES_FILE}"

cd /build # Go back to the original build directory
rm -rf "${UDEB_TMP}"

# ------------------------------------------------------------------
# 3. Copy preseed.cfg into initrd
#    (Debian wiki method: “Adding a Preseed File to the Initrd”)
# ------------------------------------------------------------------
INITRD="${WORK_DIR}/install.amd/initrd.gz"
mkdir initrd-root
cd initrd-root
gunzip -c "${INITRD}" | cpio -id --no-absolute-filenames
cp /out/preseed.cfg .
find . | cpio -o -H newc | gzip -9 > "${INITRD}"
cd ..
rm -rf initrd-root

# ------------------------------------------------------------------
# 4. Add boot parameter so installer picks up the file automatically
#    (two places: BIOS & EFI menus)
# ------------------------------------------------------------------
sed -i '/label install/,/^$/ s/append.*/& auto=true file=\/cdrom\/preseed.cfg/' \
    "${WORK_DIR}/isolinux/txt.cfg"
sed -i '/menuentry.*Install/,/^}$/ s/$/ auto=true file=\/cdrom\/preseed.cfg/' \
    "${WORK_DIR}/boot/grub/grub.cfg"

# Fallback
cp /out/preseed.cfg "${WORK_DIR}/preseed.cfg"

# ------------------------------------------------------------------
# 5. Regenerate checksums (md5sum.txt)
# ------------------------------------------------------------------
chmod u+w "${WORK_DIR}/md5sum.txt"
cd "${WORK_DIR}"
# find -follow -type f -exec md5sum {} \> md5sum.txt \;
find . -type f -not -name 'md5sum.txt' -print0 | xargs -0 md5sum > md5sum.txt
chmod u-w md5sum.txt

# ------------------------------------------------------------------
# 6. Build bootable ISO (identical vol-id, eltorito & EFI)
# ------------------------------------------------------------------
xorriso -as mkisofs \
    -V "DEBIAN_TIDY" \
    -o "/out/debian-${DEBIAN_VERSION}-amd64-netinst-preseed.iso" \
    -J -R -T \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
    "${WORK_DIR}"

# ------------------------------------------------------------------
# 7. Cleanup
# ------------------------------------------------------------------
rm -rf "${WORK_DIR}" "${REMASTER}"