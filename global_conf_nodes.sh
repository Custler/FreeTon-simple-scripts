#!/bin/bash

GLB_CONF_FILE="$1"

ip2dec(){ # Convert an IPv4 IP number to its decimal equivalent.
          declare -i a b c d;
          IFS=. read a b c d <<<"$1";
          echo "$(((a<<24)+(b<<16)+(c<<8)+d))";
}
dec2ip(){ # Convert an IPv4 decimal IP value to an IPv4 IP.
          declare -i a=$((~(-1<<8))) b=$1; 
          set -- "$((b>>24&a))" "$((b>>16&a))" "$((b>>8&a))" "$((b&a))";
          local IFS=.;
          echo "$*";
}
    
NodeNum=0

NumOfNodes=$(cat $GLB_CONF_FILE | jq '.dht.static_nodes.nodes|length')
echo "============================================================================================="
for (( i=0; i < $NumOfNodes; i++ ))
do
    CurrNodDecIP=$(cat $GLB_CONF_FILE | jq ".dht.static_nodes.nodes[$i].addr_list.addrs[0].ip")
    CurrNodePort=$(cat $GLB_CONF_FILE | jq ".dht.static_nodes.nodes[$i].addr_list.addrs[0].port")
    #echo "Dec IP of 1: $DecIP"

    CurNodeIP=$(dec2ip "$CurrNodDecIP")

    printf "Node %3d IP:port %15s:%5s \n" "$i" "${CurNodeIP}" "${CurrNodePort}"
done
echo
echo "Num of NOdes: $NumOfNodes"
echo "============================================================================================="

exit 0
