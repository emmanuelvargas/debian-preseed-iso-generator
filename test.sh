orig_iso=pve03-preseed-debian-netinst.iso
new_files=isofiles
new_iso=pve03-preseed-debian-netinst-mod.iso
mbr_template=isohdpfx.bin

# Extract MBR template file to disk
dd if="$orig_iso" bs=1 count=432 of="$mbr_template"

xorriso -as mkisofs \
   -r -J --joliet-long \
   -V 'd-live 11.5.0 xf amd64' \
   -o "$new_iso" \
   -isohybrid-mbr "$mbr_template" \
   -partition_offset 16 \
   -c isofiles/isolinux/boot.cat \
   -b isofiles/isolinux/isolinux.bin \
   -no-emul-boot -boot-load-size 4 -boot-info-table \
   -eltorito-alt-boot \
   -e boot/grub/efi.img \
   -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
   "$new_files"