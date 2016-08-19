#!/bin/bash


function select_input() {
	local TO_SELECT="$1"
	local SELECTION=$2
	echo "${TO_SELECT}" | head -n ${SELECTION} | tail -n 1
}

function selector() {
	local TO_SELECT="$(echo "$1" | sed -e 's, ,*,g')"
	local PROMPT="$2"
	MAX=$(( `echo "${TO_SELECT}" | wc -l` + 1))
	SELECT="a"

	while [[ ! ${SELECT} =~ ^([[:digit:]]*)$ && ! (${SELECT} -le ${MAX} && ${SELECT} -gt 0) ]]; do
		i=$((1))

		echo -e "\e[32m${PROMPT}:\e[0m"
		echo -en "\e[33m"
		for S in ${TO_SELECT}; do
			echo "${i}. ${S}" | sed -e 's,*, ,g'
			i=$((i+1))
		done
		if [[ ! $3 == "no_skip" ]];then echo "${i}. skip";else i=$((i-1)); fi
		echo -en "\e[0m[1-${i}]: " && read SELECT 
	done
	[[ ${SELECT} -eq ${MAX} ]] && SELECT=$((-(${MAX}+1)))
}

function common_net_config() {
	systemctl stop dhcpcd.service
	pkill dhcpcd
	INTERFACES="$(ip add show | grep '^[[:digit:]]*:\( \)*[[:alnum:]]*' -oh | cut -f 2 -d : )"

	selector "${INTERFACES}" "Please select network device"

	INTERFACE=$(select_input "${INTERFACES}" ${SELECT} | tr -d '[[:space:]]')
	ip addr flush dev ${INTERFACE}
	ip route flush dev ${INTERFACE}
	ip link set dev ${INTERFACE} down
}

function resolv_conf() {
	>&2 echo -e "\e[33mCopied a bakup file at /etc/resolv.conf.bak\e[0m"
	cp /etc/resolv.conf /etc/resolv.conf.bkp
	sed -e '/#nameserver <ip>/d' /etc/resolv.conf
	echo "#nameserver <ip>"
	
	for D in $(echo ${DNS} | sed -e 's/,/ /g'); do
		echo "nameserver ${D}"
	done
	tail -n 1 /etc/resolv.conf
}

function dhcpcd_conf() {
	>&2 echo -e "\e[33mCopied a bakup file at /etc/dhcpcd.conf.bak\e[0m"
	cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bkp
	sed "/#define static profile for ${INTERFACE}/d" /etc/dhcpcd.conf
	echo "#define static profile for ${INTERFACE}"
	echo "profile static_${INTERFACE}"
	echo "static ip_address=${IP_ADDR}/${SUBNET}"
	echo "static routers=${DEFAULT_GATEWAY}"
	echo "static domain_name_servers=$(echo ${DNS} | sed -e 's/,/ /g')"
	echo
	echo "#fallback to static profile on ${INTERFACE}"
	echo "interface ${INTERFACE}"
	echo "fallback static_${INTERFACE}"
}

function check_net_conf() {
	RESULT=0
	if [[ -n ${DEFAULT_GATEWAY} ]]; then
		echo "ping the gateway ${DEFAULT_GATEWAY}"
		echo

		ping ${DEFAULT_GATEWAY} -c 4
		R=$?
		RESULT=$((R+RESULT))
	fi
	
	if [[ -n ${DNS} ]]; then
		echo
		echo "ping the dns server"
		for D in $(echo ${DNS} | sed -e 's/,/ /g'); do
			ping ${D} -c 2
			R=$?
			RESULT=$((R+RESULT))
		done
	fi
	
	echo "ping www.google.de"
	ping www.google.de -c 4
	R=$?
	RESULT=$((R+RESULT))

	[[ $RESULT -eq 0 ]] && echo -e "\e[33mConnection could be established to the internet\e[0m" \
			    || echo -e "\e[31mConnection to the internet could not be established\e[0m"
	echo
	return ${RESULT}
}


function static_net_config() {
	common_net_config
	ip link set ${INTERFACE} up

	IP_ADDR=
	SUBNET=
	DEFAULT_GATEWAY=
	DNS=
	ANSWER=
		
	while [[ ! ${ANSWER} =~ ^(Y|y)$ ]]; do 
		echo "Please type in the network configuration"
		echo -en "\e[32mip address\e[0m: " && read IP_ADDR
		echo -en "\e[32msubnet mask [*digit*]\e[0m: " && read SUBNET
		echo -en "\e[32mdefault gateway\e[0m: " && read DEFAULT_GATEWAY
		echo -en "\e[32mdns addresses (comma seperated)\e[0m: " && read DNS 

		echo
		
		echo "-----------------------------------------------------"
		echo -e "\e[32mip adress\e[0m: ${IP_ADDR}" 
		echo -e "\e[32msubnet mask\e[0m: ${SUBNET}" 
		echo -e "\e[32mdefault gateway\e[0m: ${DEFAULT_GATEWAY}" 
		echo 
		i=$((0))
		for D in $(echo ${DNS} | sed -e 's/,/ /g'); do
			i=$((i+1))
			echo -e "\e[32mDNS (${i})\e[0m:  ${D}"
		done
		echo "-----------------------------------------------------"
		echo
		echo -en "\e[32mIs this configuration correct? [yY]\e[0m: " && read ANSWER 
	done

	echo "$(dhcpcd_conf)" > /etc/dhcpcd.conf

	dhcpcd ${INTERFACE}
}

function dhcp_net_config() {
	common_net_config
	dhcpcd ${INTERFACE}
}

loadkeys de-latin1

NET_OK=1
while [[ ! ${NET_OK} -eq 0 ]]; do
	NET_TYPE=
	while [[ ! ${NET_TYPE} =~ ^(1|2|3)$ ]]; do
		echo -e "\e[32mChoose network configuration \e[0m: "
		echo -e "\e[33m1) dhcp" 
		echo -e "2) static"
		echo -e "3) skip \e[0m"
		echo -n ": " && read NET_TYPE 
	done

	case ${NET_TYPE} in
		1 )
			dhcp_net_config 
			;;

		2 )
			static_net_config
			;;

		3)	;;
	esac

	check_net_conf
	NET_OK=$?
done

# do the partitioning

echo -e "\e[32mTime to configure your partitions\e[0m"
echo    "---------------------------------------------------------"
PARTMANAGER="$(echo -e "fdisk\ngdisk")"
EXISTS=1
while [[ ${EXISTS} -ne 0 ]];
do
	selector "${PARTMANAGER}" "Choose partition program:" "no_skip" 
	export PARTMAN=$(select_input "${PARTMANAGER}" ${SELECT})
	if [[ -z ${PARTMAN} ]]; then
		PARTMAN=fdisk 
		echo "FALLBACK to fdisk"
	fi
	which ${PARTMAN} > /dev/null 2> /dev/null
	EXISTS=$?
done

EDITED_DEVS=
echo -en "\e[32mDo you want to partition a device? [Y|n]\e[0m: " && read ANSWER
[[ -z "${ANSWER}" ]] && ANSWER="y"

while [[ ${ANSWER} =~ ^(y|Y)$ ]] ; do
	echo -e "\e[33m"
	lsblk
	echo -e "\e[0m"

	HDDS="$(lsblk -d | grep -o "sd[[:alpha:]]")"
	selector "${HDDS}" "choose a device to partition:"

	echo
	DEV=$(select_input "${HDDS}" ${SELECT})
	[[ -z "${DEV}" ]] && break

	echo -e "\e[33mpartition dev ${DEV}\e[0m" && read
	echo -e "\e[33m[press enter to continue]\e[0m" && read
	 
	${PARTMAN} /dev/${DEV}
	EDITED_DEVS+="/dev/${DEV} "
	echo
	echo -en "\e[32mDo you want to partition an other device? [Y|n]\e[0m: " && read ANSWER
	[[ -z "${ANSWER}" ]] && ANSWER="y"
done

EDITED_DEVS=$(echo ${EDITED_DEVS} | sed -e 's, ,\n,g' | sed -e '/^\s*$/d' | uniq)
echo

echo -e "\e[32mReady to format partitions..."
echo -e "The following partitions are available:\e[0m"
echo -e "\e[33m"
lsblk -o "NAME,SIZE,TYPE" | grep "sd[[:alpha:]][[:digit:]]*"
echo -e "\e[0m"


ANSWER="y"
FORMAT_TOOLS="$(ls -1 /bin/mkfs.* | sed 's,$, _PART_,g')"
FORMAT_TOOLS+="$(echo -e "\nmkswap _PART_; swapon _PART_")"
while [[ ${ANSWER} =~ ^(y|Y)$ ]] ; do
	PARTITIONS="$(lsblk -l -o "NAME,SIZE,FSTYPE" | grep "sd[[:alpha:]][[:digit:]]")"
	selector "${PARTITIONS}" "choose a partitions to format:"
	echo
	PART=$(select_input "${PARTITIONS}" ${SELECT} | tr -s ' ' | cut -f 1 -d ' ' | sed -e 's,_,,g')
	[[ -z "${PART}" ]] && break

	PARTITIONS=$(echo "${PARTITIONS}" | sed "s,${PART},_&_,g")

	selector "${FORMAT_TOOLS}" "choose a format tool for the partitions /dev/${PART}"
	TOOL=$(select_input "${FORMAT_TOOLS}" ${SELECT})
	[[ -z "${TOOL}" ]] && continue

	TOOL=$(echo ${TOOL} | sed 's,_PART_,/dev/${PART},g')

	eval "${TOOL}"
	 
	echo -en "\e[32mDo you want to format an other partition [Y|n]\e[0m: " && read ANSWER
	[[ -z "${ANSWER}" ]] && ANSWER="y"
done


PARTITIONS="$(lsblk -l -o "NAME,SIZE,FSTYPE,MOUNTPOINT" | grep "sd[[:alpha:]][[:digit:]]")"
echo 
echo -e "\e[32mLets mount your partition: \e[0m"
echo

echo "unmounting partition on /mnt"
umount -R /mnt

echo -e	"Starting with the root partition..."
echo -e "\e[0m"
selector "${PARTITIONS}" "Which Partition should be mounted at '/'"
PART=$(select_input "${PARTITIONS}" ${SELECT} | tr -s ' ' | cut -f 1 -d ' ')
echo ${PART}
[[ ! -z "${PART}" ]] && mount /dev/${PART} /mnt

PARTITIONS="$(lsblk -l -o "NAME,SIZE,FSTYPE,MOUNTPOINT" | grep "sd[[:alpha:]][[:digit:]]")"
echo -e "\e[32mNext mount the boot partition...\e[0m"
selector "${PARTITIONS}" "Which Partition should be mounted at '/boot'"
PART=$(select_input "${PARTITIONS}" ${SELECT} | tr -s ' ' | cut -f 1 -d ' ')
if [[ ! -z "${PART}" ]];then mkdir -p /mnt/boot; mount /dev/${PART} /mnt/boot; fi

PARTITIONS="$(lsblk -l -o "NAME,SIZE,FSTYPE,MOUNTPOINT" | grep "sd[[:alpha:]][[:digit:]]")"
echo -e "\e[32mNext mount the home partition...\e[0m"
selector "${PARTITIONS}" "Which Partition should be mounted at '/home'"
PART=$(select_input "${PARTITIONS}" ${SELECT} | tr -s ' ' | cut -f 1 -d ' ')
echo ${PART}
if [[ ! -z "${PART}" ]];then mkdir -p /mnt/home; mount /dev/${PART} /mnt/home; fi

YESNO="$(echo -e "Yes\nNo")"
selector "${YESNO}" "Do you need to mount other partitions?" "no_skip"
if [[ $(select_input "${YESNO}" ${SELECT}) == "Yes" ]];
then
	echo "Mount your partitions now in an other terminal and press 'enter' when done"
	echo -e "\e[32mReady? Please press enter\e[0m"
	read
fi


VIMNANO="$(echo -e "vi\nvim\nnano")"
EXISTS=1
while [[ ${EXISTS} -ne 0 ]];
do
	selector "${VIMNANO}" "Please edit the mirrorlist file: vim or nano?" 
	export EDITOR=$(select_input "${VIMNANO}" ${SELECT})
	[[ -z ${EDITOR} ]] && break
	which ${EDITOR} > /dev/null 2> /dev/null
	EXISTS=$?
done

[[ ! -z "${EDITOR}" ]] && eval "${EDITOR} /etc/pacman.d/mirrorlist"


echo
echo -e "\e[32mInstalling base system...\e[0m"
pacstrap -i /mnt base base-devel

echo
echo -e "\e[32mGenerating fstab\e[0m"
echo 

genfstab -U /mnt > /mnt/etc/fstab

YESNO="$(echo -e "Yes\nNo")"
selector "${YESNO}" "Do you want to check the fstab file?" "no_skip"
if [[ $(select_input "${YESNO}" ${SELECT}) == "Yes" ]]
then
	eval "${EDITOR} /mnt/etc/fstab" 
else
	echo -e "\e[31mWARNING: \e[33mThe fstab file should always be checked after generating, and edited in case of errors.\e[0m"
fi

source ./configure.sh
