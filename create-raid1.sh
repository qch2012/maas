#!/usr/bin/env bash

# Demo scripts to configure raid1 on multiple MAAS machines

set -e

check_dependencies() {
   local app=$1
   if !  which $app >/dev/null 2>&1; then
     echo "$app not found"
     exit 1
   fi
}

check_result() {
  if ! echo "$1" | jq empty >/dev/null 2>&1; then
    echo "$result"
    exit 1
  fi
}


if [[ ! -f ./maas-storage-lib.sh ]]; then
  echo "maas-storage-lib.sh not found in current directory"
  exit 1
else
  source maas-storage-lib.sh
fi

echo "Checking dependencies"
required_apps=(curl jq)
for i in ${required_apps[@]}; do
  check_dependencies $i
done

echo "Test connection to MAAS"
maas_api_server="10.68.10.6"
export maas_profile=admin
export maas_api_key="SfkmHhKyXE8PYkj5ta:hGyCyJ9cMM3gukxAU6:V3UQKZ3GTxVnm8SbXa7yzEvhbYehEqk9"
export maas_url=http://"$maas_api_server":5240/MAAS/api/2.0


result=$(m users)
check_result "$result"


# system_id of machines to be configured with raid1
system_ids=(bha74h)

for system_id in ${system_ids[@]}; do
  echo "-------------------------------------------------"
  echo "Configure $system_id"
  echo "Restore storage"
  result=$(restore_storage $system_id)
  check_result "$result"
  
  echo "Create raid1"
  result=$(create_raid1 $system_id md1 nvme1n1 nvme2n1)
  check_result "$result"
  device_id=$(echo "$result" | jq -r '.virtual_device.id')
  
  
  echo "format raid1 with ext4"
  result=$(format_blockdevice $system_id $device_id ext4)
  check_result "$result"
  
  
  echo "mount block device"
  result=$(mount_blockdevice $system_id $device_id /mnt/md1) 
  check_result "$result"
  
  echo "display blockdevice"
  get_blockdevices $system_id -s
done
