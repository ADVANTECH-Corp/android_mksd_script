#!/bin/bash

#Check whether it is android?
android=0
if [ -f /init.rc ]; then
	android=1
	busybox="busybox"
fi

# partition size in MB
BOOTLOAD_RESERVE=8
BOOT_ROM_SIZE=32
SYSTEM_ROM_SIZE=1536
CACHE_SIZE=512
RECOVERY_ROM_SIZE=32
DEVICE_SIZE=8
MISC_SIZE=4
DATAFOOTER_SIZE=2
METADATA_SIZE=2
FBMISC_SIZE=1
PRESISTDATA_SIZE=1

help() {
	bn=`basename $0`
	help_menu=help_menu
	echo "--------------------------------------------------------------" >$help_menu
	echo "usage $bn <option> device_node" >> $help_menu
	echo "example:		     " >>$help_menu
	if [ "${android}" -ne "1" ]; then	  
		echo "  		./mksd-android /dev/sdx	     " >>$help_menu
	else
		echo "  		sh ./mksd-android /dev/block/mmcblk0     " >>$help_menu
	fi
	echo "options:                      " >> $help_menu
	echo "  -h				displays this help message" >>$help_menu
	echo "  -s				only get partition size" >>$help_menu
	echo "--------------------------------------------------------------">>$help_menu
	cat $help_menu
	rm $help_menu
}
#check image file exist or not?
files=`ls ../image/`
if [ -z "$files" ]; then
        echo "There are no file in image folder(../image/boot.img ../image/u-boot_crc.bin ..etc)"
        exit
fi	

# check the if root?

if [ "${android}" -ne "1" ]; then	  
	userid=`id -u`
	if [ $userid -ne "0" ]; then
		echo "you're not root?"
		exit
	fi
fi


# parse command line
moreoptions=1
node="na"
cal_only=0
bootloader_offset=1
not_format_fs=0
while [ "$moreoptions" = 1 -a $# -gt 0 ]; do
	case $1 in
	    -h) help; exit ;;
	    -s) cal_only=1 ;;
	    -nf) not_format_fs=1 ;;
	    *)  moreoptions=0; node=$1 ;;
	esac
	[ "$moreoptions" = 0 ] && [ $# -gt 1 ] && help && exit
	[ "$moreoptions" = 1 ] && shift
done

if [ ! -e ${node} ]; then
	help
	exit
fi

check_node=`echo ${node} | grep mmc`
if [ -n "$check_node" ];then
	part="p"
fi

# umount device
if [ "${android}" -ne "1" ]; then	  
	umount ${node}* &> /dev/null
fi
# get total card size
seprate=40
total_size=`${busybox} fdisk -l ${node}|${busybox} sed -n '2p'|${busybox} cut -d ' ' -f 5`
total_size=`${busybox} expr ${total_size} / 1024`
boot_rom_sizeb=`${busybox} expr ${BOOT_ROM_SIZE} + ${BOOTLOAD_RESERVE}`
extend_size=`${busybox} expr ${SYSTEM_ROM_SIZE} + ${CACHE_SIZE} + ${DEVICE_SIZE} + ${MISC_SIZE} + ${FBMISC_SIZE} + ${PRESISTDATA_SIZE} + ${DATAFOOTER_SIZE} + ${METADATA_SIZE} + ${seprate}`
data_size=`${busybox} expr ${total_size} - ${boot_rom_sizeb} - ${RECOVERY_ROM_SIZE} - ${extend_size}`

# create partitions
if [ "${cal_only}" -eq "1" ]; then
	show=show
	echo "BOOT   : ${boot_rom_sizeb}MB" > $show
	echo "RECOVERY: ${RECOVERY_ROM_SIZE}MB" >> $show
	echo "SYSTEM : ${SYSTEM_ROM_SIZE}MB" >> $show
	echo "CACHE  : ${CACHE_SIZE}MB" >> $show
	echo "DATA   : ${data_size}MB" >> $show
	echo "MISC   : ${MISC_SIZE}MB" >> $show
	echo "DEVICE : ${DEVICE_SIZE}MB" >> $show
	echo "DATAFOOTER : ${DATAFOOTER_SIZE}MB" >> $show
	echo "METADATA : ${METADATA_SIZE}MB" >> $show
	echo "FBMISC   : ${FBMISC_SIZE}MB" >> $show
	echo "PRESISTDATA : ${PRESISTDATA_SIZE}MB" >> $show

	cat $show
	rm $show
	exit
fi

function copy_image_to_data
{
	echo "copy images and scripts to /data/"
	umount ${node}* &> /dev/null
	mkdir /mnt/android_image
	mount ${node}${part}4 /mnt/android_image
	mkdir /mnt/android_image/mkimage
	cp -rf ../image /mnt/android_image/mkimage
	sync
	cp -rf ../scripts /mnt/android_image/mkimage
	sync
	umount ${node}* &> /dev/null
	rm -r /mnt/android_image
	echo "copy images and scripts to /data/ finish"
}

function format_android
{
if [ "${android}" -ne "1" ]; then
	echo "formating sdcard"
	mkfs.ext4 ${node}${part}4 -Ldata &> /dev/null;sync
	mkfs.ext4 ${node}${part}5 -Lsystem &> /dev/null;sync
	mkfs.ext4 ${node}${part}6 -Lcache &> /dev/null;sync
	mkfs.ext4 ${node}${part}7 -Ldevice &> /dev/null;sync
	echo "formating sdcard done"
else
	echo "formating emmc"
	${busybox} mke2fs -T ext4 ${node}${part}4 -Ldata &> /dev/null;sync
	${busybox} mke2fs -T ext4 ${node}${part}5 -Lsystem &> /dev/null;sync
	${busybox} mke2fs -T ext4 ${node}${part}6 -Lcache &> /dev/null;sync
	${busybox} mke2fs -T ext4 ${node}${part}7 -Ldevice &> /dev/null;sync
	echo "formating emmc done"
fi

}

function flash_android
{
    echo "flashing android images"
    dd if=../image/u-boot_crc.bin.crc of=${node} bs=512 seek=2  &> /dev/null;sync 
    dd if=../image/u-boot_crc.bin of=${node} bs=512 seek=3 &> /dev/null;sync
    echo "dd u-boot.bin done"
    dd if=../image/boot.img of=${node}${part}1 &> /dev/null;sync
    echo "dd boot.img done"

    # use pc tool for sd, buildin tool for emmc
    if [ "${android}" -ne "1" ]; then
        ./../image/simg2img ../image/system.img ../image/system_raw.img
    else
        simg2img ../image/system.img ../image/system_raw.img
    fi
    
    dd if=../image/system_raw.img of=${node}${part}5 bs=512k &> /dev/null;sync
    echo "dd system.img done"
    dd if=../image/recovery.img of=${node}${part}2 bs=512k &> /dev/null;sync
    echo "dd recovery.img done"


    echo "flashing android images done"
    if [ "${android}" -ne "1" ]; then	  
    	copy_image_to_data  
    fi
}


# destroy the partition table
dd if=/dev/zero of=${node} bs=1024 count=1 &> /dev/null;sync

#partition
echo "partition start"
tmp=partitionfile
cs=$(${busybox} fdisk -l ${node}|${busybox} sed -n '4p'|${busybox} cut -d ' ' -f 3)
if [ $cs == "cylinders" ];then
	echo u > $tmp
	echo n>> $tmp
else
	echo n > $tmp
fi
echo p >> $tmp
echo 1 >> $tmp
echo +10M >> $tmp
echo +36M >> $tmp
echo n >> $tmp
echo p >> $tmp
echo 2 >> $tmp
echo +48M >> $tmp
echo +36M >> $tmp
echo n >> $tmp
echo e >> $tmp
echo 3 >> $tmp
echo +86M >> $tmp
echo +2260M >> $tmp
echo n >> $tmp
echo p >> $tmp
echo +2346M >> $tmp
echo "" >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +1700M >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +500M >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +12M >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +12M >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +12M >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +4M >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +4M >> $tmp
echo n >> $tmp
echo "" >> $tmp
echo +2M >> $tmp
echo w >> $tmp
${busybox} fdisk ${node} < $tmp &> /dev/null 
rm $tmp
echo "partition done"

format_android
flash_android

