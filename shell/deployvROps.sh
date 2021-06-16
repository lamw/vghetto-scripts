#!/bin/bash
# Author: William Lam
# Website: www.williamlam.com
# Product: VMware vRealize Operations Manager 6.0
# Description: Wrapper script to deploy vRealize Operations Manager 6.0 (vROps)
# Reference: http://www.williamlam.com/2014/12/automate-deployment-configuration-of-vrealize-operations-manager-6-0-part-1.html

# Configurations 

# vROps OVF
VROPS_OVA=/Users/lamw/desktop/vRealize-Operations-Manager-Appliance-6.0.0.2263110_OVF10.ova

# VM Settings
VROPS_DISPLAY_NAME=vrops6
VROPS_PORTGROUP="VM Network"
VROPS_DATASTORE=mini-local-datastore-1
VROPS_DISK_TYPE=thin
VROPS_IPADDRESS=192.168.1.150
VROPS_NETMASK=255.255.255.0
VROPS_GATEWAY=192.168.1.1
VROPS_DNS=192.168.1.1
VROPS_IPPROTOCOL=IPv4
VROPS_DEPLOYMENT_SIZE=xsmall

# vCenter or ESX(i)
VCENTER_HOSTNAME=192.168.1.119
VCENTER_USERNAME=root
VCENTER_PASSWORD=vmware
ESXI_HOSTNAME=192.168.1.200

# Enable SSH
ENABLE_SSH=true

############## DO NOT EDIT BEYOND HERE #################

verify() {
	if [ ! -e ${VROPS_OVA} ]; then
		echo "Unable to locate \"${VROPS_OVA}\"!"
		exit 1
	fi

	echo "Would you like to deploy the following configuration for vRealize Operations Manager?"
	echo -e "\tVMware vRealize Operations Manager Virtual Appliance: ${VROPS_OVA}"
	echo -e "\tvROps Display Name: ${VROPS_DISPLAY_NAME}"
	echo -e "\tvROps IP Address: ${VROPS_IPADDRESS}"
	echo -e "\tvROps Netmask: ${VROPS_NETMASK}"
	echo -e "\tvROps Gateway: ${VROPS_GATEWAY}"
	echo -e "\tvROps DNS: ${VROPS_DNS}"
	echo -e "\tvROps IP Protocol: ${VROPS_IPPROTOCOL}"
	echo -e "\tvROps Enable SSH: ${ENABLE_SSH}"
	echo -e "\tvROps Portgroup: ${VROPS_PORTGROUP}"
	echo -e "\tvROps Datastore: ${VROPS_DATASTORE}"
	echo -e "\tvROps Disk Type: ${VROPS_DISK_TYPE}"
	echo -e "\tvCenter Server: ${VCENTER_HOSTNAME}"
	echo -e "\tTarget ESX(i) host: ${ESXI_HOSTNAME}"

	echo -e "\ny|n?"

	read RESPONSE
        case "$RESPONSE" in [yY]|yes|YES|Yes)
                ;;
                *) echo "Quiting installation!"
                exit 1
                ;;
        esac
}

deployvROpsOVA() {
	#OVFTOOL_BIN=/usr/bin/ovftool
	OVFTOOL_BIN="/Applications/VMware OVF Tool/ovftool"

	if [ ! -e ${OVFTOOl_BIN} ]; then
		echo "ovftool does not look like it's installed!"
		exit 1
	fi

	echo "Deploying VMware vRealize Operations Manager Appliance: ${VROPS_DISPLAY_NAME} ..."
	"${OVFTOOL_BIN}" --powerOn --acceptAllEulas --noSSLVerify --skipManifestCheck --allowAllExtraConfig --X:enableHiddenProperties --deploymentOption=${VROPS_DEPLOYMENT_SIZE} "--net:Network 1=${VROPS_PORTGROUP}" --datastore=${VROPS_DATASTORE} --diskMode=${VROPS_DISK_TYPE} --name=${VROPS_DISPLAY_NAME} --prop:vami.DNS.vRealize_Operations_Manager_Appliance=${VROPS_DNS} --prop:vami.gateway.vRealize_Operations_Manager_Appliance=${VROPS_GATEWAY} --prop:vami.ip0.vRealize_Operations_Manager_Appliance=${VROPS_IPADDRESS} --prop:vami.netmask0.vRealize_Operations_Manager_Appliance=${VROPS_NETMASK} --prop:guestinfo.cis.appliance.ssh.enabled=${ENABLE_SSH} ${VROPS_OVA} vi://${VCENTER_USERNAME}:${VCENTER_PASSWORD}@${VCENTER_HOSTNAME}/?dns=${ESXI_HOSTNAME}
}

verify
deployvROpsOVA
echo "VMware vRealize Operations Manager Virtual Appliance ${VROPS_DISPLAY_NAME} has successfully been deployed!"
