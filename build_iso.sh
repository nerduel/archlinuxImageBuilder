#!/bin/bash


ROOT_DIR=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)
ISO_PATH=${1}


if [[ -z ${ISO_PATH} ]]; then
	echo "ABORT: please specify a archlinux iso_file"
	exit 1
fi

ISO_PATH="$(cd `dirname ${ISO_PATH}` &&pwd)/`basename "${ISO_PATH}"`"

echo ${ISO_PATH}
if [[ ! -f ${ISO_PATH} ]]; then
	echo "ABORT: please specify a archlinux iso_file with correct path"
	exit 1
fi

ISO_NAME="ARCH_$(basename ${ISO_PATH} | cut -f 2 -d - | sed -e 's,\.[[:digit:]][[:digit:]]$,,' -e 's,\.,,g')"
WORK_PATH="${ROOT_DIR}/output/`date +%Y-%m-%d`-archiso"
mkdir -p "${ROOT_DIR}/output"
MOUNT_PATH="${ROOT_DIR}/mnt/archiso"

echo "preparing build environment"
echo
mkdir -p ${MOUNT_PATH}
echo "mount iso"
echo
mount -t iso9660 -o loop ${ISO_PATH} ${MOUNT_PATH}
echo "copy mounted iso into own working directory"
echo
cp -a ${MOUNT_PATH} ${WORK_PATH}

umount ${MOUNT_PATH}

echo "prepare new rootfs: unsquash old airootfs.sfs"

cd ${WORK_PATH}/arch/x86_64
unsquashfs airootfs.sfs 
echo "${ROOT_DIR}/output"
mv squashfs-root ${ROOT_DIR}/output/

echo "prepare new rootfs: copy install scripts"
echo
cp ${ROOT_DIR}/input/*.sh ${ROOT_DIR}/output/squashfs-root/root/

echo "prepare new rootfs: mksquash new rootfs"
echo
rm ${WORK_PATH}/arch/x86_64/airootfs.sfs
mksquashfs ${ROOT_DIR}/output/squashfs-root ${WORK_PATH}/arch/x86_64/airootfs.sfs
rm -r ${ROOT_DIR}/output/squashfs-root

echo "prepare new rootfs: build md5 hash"
echo
md5sum ${WORK_PATH}/arch/x86_64/airootfs.sfs > ${WORK_PATH}/arch/x86_64/airootfs.md5

iso_label="${ISO_NAME}"
xorriso -as mkisofs \
	-iso-level 3 \
 	-full-iso9660-filenames \
 	-volid "${iso_label}" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
 	-isohybrid-mbr ${WORK_PATH}/isolinux/isohdpfx.bin \
	-eltorito-alt-boot \
	-e EFI/archiso/efiboot.img \
	-no-emul-boot -isohybrid-gpt-basdat \
 	-output ${ROOT_DIR}/output/${ISO_NAME}-custom.iso \
	${WORK_PATH}

rm -rf ${WORK_PATH}
