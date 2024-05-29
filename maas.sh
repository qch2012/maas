#!/usr/bin/env bash
set -o pipefail

if [ -z "$maas_api_key" ]; then
  echo "maas_api_key not found, please execute maas-login.sh"
  return
fi

# read maas profile from env variable
profile="$maas_profile"


m(){
  # curl maas api
    _usage(){
        echo "Usage: ${FUNCNAME[1]} <resource> <-cud> [parameters]  "
        echo ""
        printf "%-30s %-30s\n" "<resource> -g" "Get MAAS resources"
        printf "%-30s %-30s\n" "<resource> -c [parameters]" "Create MAAS resources"
        printf "%-30s %-30s\n" "<resource> -u [parameters]" "Update MAAS resources"
        printf "%-30s %-30s\n" "<resource> -d" "Delete MAAS resources"
        printf "%-30s %-30s\n" "-h"  "Display help"
    }
    OPTIND=1
    while getopts ":h" opt; do
      case $opt in
           h|*)
               _usage
               shift 
               return 
               ;;
      esac
    done
    consumer_key=$(echo $maas_api_key | cut -d ":" -f1)
    token=$(echo $maas_api_key | cut -d ":" -f2)
    secret=$(echo $maas_api_key | cut -d ":" -f3)
    auth_header="Authorization: OAuth oauth_consumer_key=\"$consumer_key\",oauth_token=\"$token\",oauth_signature_method=\"PLAINTEXT\",oauth_version=\"1.0\",oauth_signature=\"%26$secret\""

    resource=$1
    #if resource url doesn't contain ? , ensure it ends with /
    if ! grep -q ? <<< "$resource"; then
      if [[ "${resource: -1}" != "/" ]]; then
        resource="$resource/"
      fi
    fi
    shift

    curl_args=(-sL -w "\n" -H "$auth_header,oauth_timestamp=\"$(date +%s)\",oauth_nonce=\"$(date +%s%N)\"" "${maas_url}/${resource}")

    OPTIND=1
    while getopts "cudg" opt; do
        case "$opt" in
            c)
               # post
               shift
               curl_args+=(-X POST)
               for i in "$@"; do
                  curl_args+=(-F "$i")
               done
               ;;
            u)
               # put
               shift
               curl_args+=(-X PUT)
               for i in "$@"; do
                  curl_args+=(-F "$i")
               done
               ;;
            d)
               # delete
               shift
               curl_args+=(-X DELETE)
               ;;
           g|*)
               # get
               curl_args+=(-H "Accept: application/json" -X GET "$@")
               ;;
        esac
    done
    #curl_args+=(-H "Accept: application/json" -X GET "$@")
    curl "${curl_args[@]}"
}

process_args(){
  verb="GET"
  OPTIND=1
  while getopts ":hc:u:d:" opt; do
     case "$opt" in
      c)
          verb="POST"
          shift
          m_args=("$resource" -c "$@")
          return
          ;;
      u)
         verb="PUT"
         shift
         id=$1
         shift
         m_args=("$resource"/$id/ -u "$@")
         return
         ;;
      d)
          verb="DELETE"
          shift
          id=$1
          m_args=("$resource/$id" -d)
          return
          ;;
      h|*)
           return 1
           ;;
    esac
  done
}

common_usage(){
  local resource=$1
  echo "MAAS domains management"
  echo "Usage: ${FUNCNAME[1]} <-cudh>"
  echo ""
  echo "list $resource"
  echo " "
  echo "optional arguments"
  printf "%-30s %-30s\n" "?<key=value>:" "query $resource"
  printf "%-30s %-30s\n" "-c <key=value>:" "create a $resource"
  printf "%-30s %-30s\n" "-u <id or name> <key=value>:" "update a $resource"
  printf "%-30s %-30s\n" "-d <id or name>:" "delete a $resource"
  printf "%-30s %-30s\n" "-h:" "help"
}

jquery(){
  # execute maas -X GET query with jq filter
  local result="$1"
  local query="$2"
  shift 2
  local column_args=("$@")

  if echo "$result" | jq empty >/dev/null 2>&1 ; then
    echo "$result"  | jq -r "$query | @tsv"  | column "${column_args[@]}"
  else
    echo "$result"
  fi
}

mdomains(){
  resource=domains

  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi

  records=$(m "$resource"/"$@")
  query='.[]|
        [
          .id,
          .name,
          .is_default,
          .authoritative,
          .resource_record_count
        ]'
  columns=(-ts  $'\t' -N "ID,NAME,IS_DEFAULT,AUTHORITATIVE,RECORDS_COUNT")
  jquery "$records" "$query" "${columns[@]}"
}

mdnsresources(){
  resource="dnsresources"

  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi

  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .id,
           .fqdn,
           .address_ttl,
           (.ip_addresses[].ip|tostring)
         ]'
  columns=(-ts  $'\t' -N "ID,FQDN,ADDRESS_TTL,IP")
  jquery "$records" "$query" "${columns[@]}"
}

mdnsresourcerecords(){
  resource="dnsresourcerecords"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
          [
            .id,
            .fqdn,
            .rrtype,
            .rrdata,
            .ttl
          ]'
  columns=(-ts  $'\t' -N "ID,FQDN,RRTYPE,RRDATA,TTL")
  jquery "$records" "$query" "${columns[@]}"
}

mfabrics(){
  resource="fabrics"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi

  records=$(m "$resource"/"$@")
  query='.[]|
         [
           [.name],
           [.id],
           [.vlans[]|[.id, .name, .vid, .mtu,.relay_vlan, .dhcp_on, .external_dhcp, .space]]
         ] | transpose[] | flatten(1)'
  columns=(-ts  $'\t' -N "FABRIC_NAME,ID,VLAN_ID,VLAN_NAME,VID, VLAN_MTU, RELAY_VLAN,DHCP_ON,External_DHCP,SPACE")
  jquery "$records" "$query" "${columns[@]}"
}

mspaces(){
  resource="spaces"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi

  records=$(m "$resource"/"$@")
  query='.[]|
         [
           [.id],
           [.name],
           [.vlans[]|[.id, .name, .vid]]
         ] | transpose[] | flatten(1)'
  columns=(-ts  $'\t' -N "ID,NAME,VLAN_ID,VLAN_NAME,VID")
  jquery "$records" "$query" "${columns[@]}"
}

mvlans(){
  #  
  if [[ $# -lt 1 ]]; then
    echo "require fabric system_id"
    return
  fi
  fabric=$1
  resource="fabrics/$fabric/vlans"
  shift 

  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .id,
           .name,
           .vid,
           .mtu,
           .fabric,
           .space
         ]'
  columns=(-ts  $'\t' -N "ID,NAME,VID,MTU,FABRIC,SPACE")
  jquery "$records" "$query" "${columns[@]}"
}

msubnets(){
  resource="subnets"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .id,
           .name,
           .vlan.fabric,
           .vlan.fabric_id,
           .space,
           .cidr,
           .gateway_ip,
           .allow_proxy,
           .allow_dns,
           (.dns_servers|tostring),
           .managed,
           .vlan.id,
           .vlan.vid,
           .vlan.mtu
         ]'
  columns=(-ts  $'\t' -N "ID,NAME,FABRIC_NAME,FABRIC_ID,SPACE,CIDR,GATEWAY,ALLOW-PROXY,ALLOW-DNS,DNS-SERVERS,MANAGED,VLAN-ID,VLAN-VID,VLAN-MTU")
  jquery "$records" "$query" "${columns[@]}"
}

mvmhosts(){
  resource="vm-hosts"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .id,
           .name,
           .type,
           .version,
           .zone.name,
           .host.system_id,
           .total.cpu,
           (.total.memory/1024),
           (.total.local_storage/(1024*1024*1024)|round),
           .pool.name,
           .storage_pools[].type
         ]'
  columns=(-ts  $'\t' -N "ID,NAME,TYPE,VERSION,ZONE,HOST_SYSID,CPU,RAM-GB,STORAGE-GB,POOL,POOL_TYPE")
  jquery "$records" "$query" "${columns[@]}"
}

mzones(){
  resource="zones"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .id,
           .name,
           .description
         ]'
  columns=(-ts  $'\t' -N "ID,NAME,DESCRIPTION" -W DESCRIPTION)
  jquery "$records" "$query" "${columns[@]}"
}

mnodes(){
  resource="nodes"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .node_type_name,
           .hostname,
           .system_id,
           .cpu_count,
           try(.memory/1024|round),
           .osystem,
           .distro_series,
           .status_name,
           (.power_type + ":" + .power_state),
           (.tag_names|tostring)
         ]'
  columns=(-ts  $'\t' -N "TYPE,HOSTNAME,SYS_ID,CPU,RAM,OS,SERIES,STATUS,POWER,TAGS" -W TAGS)
  jquery "$records" "$query" "${columns[@]}"
}

mmachines(){
  resource="machines"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .system_id,
           .hostname,
           .cpu_count,
           (.memory/1024|tostring) + "G",
           (.storage/1000|round|tostring) + "G",
           .osystem,
           .distro_series,
           .zone.name,
           .status_name,
           .commissioning_status_name,
           .testing_status_name,
           .power_type,
           .power_state,
           (.tag_names|tostring)
         ]'
  columns=(-ts  $'\t' -N "ID,HOSTNAME,CPU,RAM,STORAGE,OS,SERIES,ZONE,STATUS,COMMISION,TESTING,POWER,POWER_STATE,TAGS" -W TAGS)
  jquery "$records" "$query" "${columns[@]}"
}

mdevices(){
  resource="devices"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
          [
            .system_id,
            .fqdn,
            .zone.name,
            (.ip_addresses|tostring)
          ]'
  columns=(-ts  $'\t' -N "SYS_ID,FQDN,ZONE,IP" -W IP)
  jquery "$records" "$query" "${columns[@]}"
}

mtags(){
  # parameters
  # required: name
  # optional: comment, definition, kernel_opts
  resource="tags"
  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "$resource"/"$@")
  query='.[]|
         [
           .name,
           .definition,
           .comment,
           .kernel_opts
         ]'
  columns=(-ts  $'\t' -N "NAME,DEFINITION,COMMENT,KERNEL_OPTS" -W KERNEL_OPTS)
  jquery "$records" "$query" "${columns[@]}"
}

minterfaces(){
  #  
  if [[ $# -lt 1 ]]; then
    echo "require node system_id"
    return
  fi
  resource="interfaces"
  node=$1
  shift 

  if ! process_args "$@" ; then
    common_usage $resource
    return
  fi

  if [[ $verb != "GET" ]]; then
    m "${m_args[@]}"
    return
  fi
  records=$(m "nodes/$node/$resource"/"$@")
  query='.[]|
         [
           .name,
           .type,
           .id,
           .enabled,
           .link_connected,
           .effective_mtu,
           .vlan.fabric,
           .vlan.vid,
           .vlan.space,
           (.links[].subnet.name),
           (.links[].subnet.cidr),
           (.links[].subnet.id)
         ]'
  columns=(-ts  $'\t' -N "NAME,TYPE,ID,ENABLED,CONNECTED,MTU,FABRIC,VID,SPACE,SUBNET,CIDR,SUB_ID")
  jquery "$records" "$query" "${columns[@]}"
}
