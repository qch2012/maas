#!/bin/bash



# call MAAS API
m(){
    _usage(){
        echo "MAAS API wrapper"
        echo "Usage: ${FUNCNAME[1]} <resource> <-cudg> [parameters]"
        echo ""
        printf "%-30s %-30s\n" "<resource> -g" "Get MAAS resources"
        printf "%-30s %-30s\n" "<resource> -c [parameters]" "Create MAAS resources"
        printf "%-30s %-30s\n" "<resource> -u [parameters]" "Update MAAS resources"
        printf "%-30s %-30s\n" "<resource> -d" "Delete MAAS resources"
        printf "%-30s %-30s\n" "-h" "Display help"
    }

    OPTIND=1
    while getopts ":h" opt; do
        case $opt in
            h|*)
                _usage
                return
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # Ensure maas_api_key is set
    if [ -z "$maas_api_key" ]; then
        echo "Error: MAAS API key (maas_api_key) not set."
        return 1
    fi

    consumer_key=$(echo $maas_api_key | cut -d ":" -f1)
    token=$(echo $maas_api_key | cut -d ":" -f2)
    secret=$(echo $maas_api_key | cut -d ":" -f3)
    auth_header="Authorization: OAuth oauth_consumer_key=\"$consumer_key\",oauth_token=\"$token\",oauth_signature_method=\"PLAINTEXT\",oauth_version=\"1.0\",oauth_signature=\"%26$secret\""

    resource=$1
    #Ensure resource URL end with '/' if it doesn't contain '?',  with the exception of parition resource
    if ! grep -q '?' <<< "$resource"; then
        if [[ "${resource: -1}" != "/" ]] && [[ ! "$resource" =~ partition/ ]]; then
           resource="$resource/"
        fi
    fi
    shift 

    curl_args=(-sL -w "\n" -H "$auth_header,oauth_timestamp=\"$(date +%s)\",oauth_nonce=\"$(date +%s%N)\"" "${maas_url}/${resource}")

    OPTIND=1
    while getopts "cudg" opt; do
        case "$opt" in
            c)
                # POST
                shift
                curl_args+=(-X POST)
                for i in "$@"; do
                    curl_args+=(-F "$i")
                done
                ;;
            u)
                # PUT
                shift
                curl_args+=(-X PUT)
                for i in "$@"; do
                    curl_args+=(-F "$i")
                done
                ;;
            d)
                # DELETE
                shift
                curl_args+=(-X DELETE)
                ;;
            g|*)
                # GET
                curl_args+=(-H "Accept: application/json" -X GET "$@")
                ;;
        esac
    done

    curl "${curl_args[@]}"
}


restore_storage() {
  usage() {
    echo "Restore a node's storage config to commissioning state"
    echo "usage: ${FUNCNAME[1]} <system_id>"
  }
  if [[ $# -lt 1 ]]; then 
    usage
    return 1
  fi
  local system_id=$1
  m machines/$system_id/?op=restore_default_configuration -c
}

get_blockdevices() {
  usage() {
    echo "Get the detail of a block device"
    echo "usage: ${FUNCNAME[1]} <system_id> <-s>"
    echo "-s: print summary"
  }
  if [[ $# -lt 1 ]]; then 
    usage
    return 1
  fi
  local system_id=$1
  local query col_args
  if [[ $2 == '-s' ]]; then
     query='.[]| [
            .id, 
            .name,  
            (.size/(1024*1024*1024)|round|tostring + "GB"),
            .filesystem.fstype,
            .filesystem.mount_point,
            .used_for
           ]'
     col_args=(-ts $'\t' -N ID,Device,Size,FStype,Mount,Usage -c $(tput cols))
     m nodes/$system_id/blockdevices/ | jq -r "$query|@tsv" | column "${col_args[@]}"
  else
     m nodes/$system_id/blockdevices/
  fi
}

get_raids() {
  usage() {
    echo "usage: ${FUNCNAME[1]} <system_id> <-s>"
    echo "-s: print summary"
  }
  if [[ $# -lt 1 ]]; then 
    usage
    return 1
  fi
  local system_id=$1
  local cmd="m nodes/$system_id/raids"
  local query col_args
  if [[ $2 == '-s' ]]; then
     query='.[]| [.id, .name, .level, .virtual_device.id]'
     col_args=(-ts $'\t' -N ID,Name,Level,Device_ID -c $(tput cols))
    eval "$cmd" | jq -r "$query|@tsv" | column "${col_args[@]}"
  else 
    eval "$cmd"
  fi
}

create_raid1() {
  usage() {
    echo "Create RAID1"
    echo "usage: ${FUNCNAME[1]} <system_id> <raid-name> <device-1> <device-2>"
  }
  if [[ $# -lt 4 ]]; then 
    usage
    return 1
  fi
  local blk_id system_id=$1 name=$2 d1=$3 d2=$4
  m nodes/$system_id/raids -c name=$name level="raid-1" block_devices=$d1 block_devices=$d2
}

create_raid10() {
  usage() {
    echo "Create RAID10"
    echo "usage: ${FUNCNAME[1]} <system_id> <raid-name> <device-1> <device-2> <device-3> <device-4>"
  }
  if [[ $# -lt 6 ]]; then 
    usage
    return 1
  fi
  # create raid10
  local blk_id system_id=$1 name=$2 d1=$3 d2=$4 d3=$5 d4=$6
  m nodes/$system_id/raids -c name=$name level="raid-10" block_devices=$d1 block_devices=$d2 block_devices=$d3 block_devices=$d4
}

format_blockdevice() {
  usage() {
    echo "Format block device with file system"
    echo "usage: ${FUNCNAME[1]} <system_id> <block_id> <fs-type>"
  }
  if [[ $# -lt 3 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2 fs_type=$3 
  m nodes/$system_id/blockdevices/$blk_id/?op=format -c fstype=$3
}

unformat_blockdevice() {
  usage() {
    echo "Unformat block device"
    echo "usage: ${FUNCNAME[1]} <system_id> <block_id>"
  }
  if [[ $# -lt 2 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2 
  m nodes/$system_id/blockdevices/$blk_id/?op=unformat -c 
}

mount_blockdevice() {
  usage() {
    echo "Mount a block device"
    echo "usage: ${FUNCNAME[1]} <system_id> <block_id> <mount_point> <mount_options>"
    echo "optional: <mount_options>"
  }
  if [[ $# -lt 3 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2 mnt="$3" mnt_opt="$4"
  m nodes/$system_id/blockdevices/$blk_id/?op=mount -c mount_point="$mnt" mount_options="$mnt_opt"
}

unmount_blockdevice() {
  usage() {
    echo "Unmount a block device"
    echo "usage: ${FUNCNAME[1]} <system_id> <block_id>"
  }
  if [[ $# -lt 2 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2
  m nodes/$system_id/blockdevices/$blk_id/?op=unmount -c
}

create_partition() {
  usage() {
    echo "usage: ${FUNCNAME[1]} <system_id> <blockdevice_id> <size> <bootable>"
    echo "size: size in MB, GB or TB, if size is not specified, use all space of the block device"
    echo "bootable: optional, to mark parition bootable"
  }
  if [[ $# -lt 2 ]]; then 
    usage
    return 1
  fi
  local params=()
  local bytes
  local system_id=$1 blk_id=$2 size=$3 
  case ${size: -2} in 
      MB)
          # increment of 4.19MB
          bytes=$(echo "${size%MB}*1024*1024" | bc)
          ;;
      GB)
          bytes=$(echo "${size%GB}*1000*1000*1000" | bc)
          ;;
      TB)
          bytes=$(echo "${size%TB}*1000*1000*1000*1000" | bc)
          ;;
      *)
          usage
          return 1
          ;;
  esac
  params+=(size=$bytes)
  if [[ $4 == "bootable" ]]; then
     params+=(bootable=true)
  fi
  if [[ ${#params[@]} -ne 0 ]]; then
     m nodes/$system_id/blockdevices/$blk_id/partitions/ -c "${params[@]}"
  else
     m nodes/$system_id/blockdevices/$blk_id/partitions/ -c
  fi
}

get_partitions() {
  usage() {
    echo "Get paritions of a block device"
    echo "usage: ${FUNCNAME[1]} <system_id> <blockdevice_id> <-s>"
    echo "-s:  print summary in tabular format"
  }
  if [[ $# -lt 2 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2
  local cmd="m nodes/$system_id/blockdevices/$blk_id/partitions"
  local query col_args
  if [[ $3 == '-s' ]]; then
     query='.[]| [
      .device_id,.id, .path, (.size/(1000*1000*1000)|.*pow(10;2)|round/pow(10;2)|tostring + "GB"), 
      .filesystem.fstype//empty, .filesystem.mount_point, .filesystem.mount_options//empty]'
     col_args=(-ts $'\t' -N Device_ID,PARTION_ID,PATH,SIZE,FS,MOUNT,MOUNT_OPT -c $(tput cols))
    eval "$cmd" | jq -r "$query|@tsv" | column "${col_args[@]}"
  else 
    eval "$cmd"
  fi
}


format_partition() {
  usage() {
    echo "usage: ${FUNCNAME[1]} <system_id> <blockdevice_id> <partition_id> <fstype>"
  }
  if [[ $# -lt 4 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2 part_id=$3 fs_type=$4 
  m nodes/$system_id/blockdevices/$blk_id/partition/$part_id?op=format -c fstype=$fs_type
}

unformat_partition() {
  usage() {
    echo "usage: ${FUNCNAME[1]} <system_id> <blockdevice_id> <partition_id>"
  }
  if [[ $# -lt 3 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2 part_id=$3 fs_type=$4 
  m nodes/$system_id/blockdevices/$blk_id/partition/$part_id?op=unformat -c 
}

mount_partition() {
  usage() {
    echo "usage: ${FUNCNAME[1]} <system_id> <blockdevice_id> <partition_id> <mount_point> <mount_options>"
    echo "optional:  mount_options"
  }
  if [[ $# -lt 4 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2 part_id=$3 mnt="$4" mnt_opt="$5"
  if [[ -n $mnt_opt ]]; then
    m nodes/$system_id/blockdevices/$blk_id/partition/$part_id?op=mount -c mount_point="$mnt" mount_options="$mnt_opt"
  else
    m nodes/$system_id/blockdevices/$blk_id/partition/"$part_id"?op=mount -c mount_point="$mnt"
  fi
}

unmount_partition() {
  usage() {
    echo "usage: ${FUNCNAME[1]} <system_id> <blockdevice_id> <partition_id>"
  }
  if [[ $# -lt 3 ]]; then 
    usage
    return 1
  fi
  local system_id=$1 blk_id=$2  part_id=$3 mnt="$4" mnt_opt="$5"
  m nodes/$system_id/blockdevices/$blk_id/partition/$part_id?op=unmount -c
}

