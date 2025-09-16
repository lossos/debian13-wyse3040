#!/usr/bin/env bash
set -euo pipefail

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