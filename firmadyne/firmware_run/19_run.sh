#!/bin/bash

set -u

ARCHEND=mipseb
IID=19

if [ -e ./firmadyne.config ]; then
    source ./firmadyne.config
elif [ -e ../firmadyne.config ]; then
    source ../firmadyne.config
elif [ -e ../../firmadyne.config ]; then
    source ../../firmadyne.config
else
    echo "Error: Could not find 'firmadyne.config'!"
    exit 1
fi

IMAGE=`get_fs ${IID}`
KERNEL=`get_kernel ${ARCHEND}`
QEMU=`get_qemu ${ARCHEND}`
QEMU_MACHINE=`get_qemu_machine ${ARCHEND}`
QEMU_ROOTFS=`get_qemu_disk ${ARCHEND}`
WORK_DIR=`get_scratch ${IID}`


TAPDEV_0=tap${IID}_0
HOSTNETDEV_0=${TAPDEV_0}
echo "Creating TAP device ${TAPDEV_0}..."
sudo tunctl -t ${TAPDEV_0} -u ${USER}


echo "Bringing up TAP device..."
sudo ip link set ${HOSTNETDEV_0} up
sudo ip addr add 192.168.0.99/24 dev ${HOSTNETDEV_0}

echo "Adding route to 192.168.0.100..."
sudo ip route add 192.168.0.100 via 192.168.0.100 dev ${HOSTNETDEV_0}


function cleanup {
    pkill -P $$
    
echo "Deleting route..."
sudo ip route flush dev ${HOSTNETDEV_0}

echo "Bringing down TAP device..."
sudo ip link set ${TAPDEV_0} down


echo "Deleting TAP device ${TAPDEV_0}..."
sudo tunctl -d ${TAPDEV_0}

}


trap cleanup EXIT

 #AFL="../afl-fuzz -t 800000+ -i ../inputs -o ../outputs -QQ --"
AFL="../afl-fuzz -t 800000+ -i ../inputs -o ../outputs -QQ --"
QEMU="../qemu_mode/qemu/mips-softmmu/qemu-system-mips"
#QEMU=" ../../../tmp/DECAF/decaf/mipsel-softmmu/qemu-system-mipsel"
#QEMU="../../../tmp/qemu/mipsel-softmmu/qemu-system-mipsel"
KERNEL="./binaries/vmlinux.mipseb" #vmlinux_3.2.1_mipsel
echo ${KERNEL}
#IMAGE="./scratch/19/image.qcow2"
echo ${QEMU_ROOTFS}
echo ${IMAGE}


echo "Starting firmware emulation... use Ctrl-a + x to exit"
sleep 1s

${AFL} \
${QEMU} -m 256 -monitor telnet:127.0.0.1:4444,server -M ${QEMU_MACHINE} -kernel ${KERNEL} \
    -drive if=ide,format=raw,file=${IMAGE} -append "root=${QEMU_ROOTFS} console=ttyS0 nandsim.parts=64,64,64,64,64,64,64,64,64,64 rdinit=/firmadyne/preInit.sh rw debug ignore_loglevel print-fatal-signals=1 user_debug=31 firmadyne.syscall=0" \
    -nographic \
    -net nic,vlan=0 -net tap,vlan=0,id=net0,ifname=${TAPDEV_0},script=no -net nic,vlan=1 -net socket,vlan=1,listen=:2001 -net nic,vlan=2 -net socket,vlan=2,listen=:2002 -net nic,vlan=3 -net socket,vlan=3,listen=:2003 \
    -aflFile @@ | tee ${WORK_DIR}/qemu.final.serial.log
#../qemu_mode/qemu/qemu-img convert -f raw -O qcow2 ./scratch/19/image.raw ./scratch/19/image.qcow2
