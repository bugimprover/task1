#!/bin/bash
vm=$1
path_to_rule_file="/etc/pve/firewall/${vm}.fw"

function gen_aws_command {
    rule_line=$1
    sg_id=$3
    if [ "$2" = "IN" ]; then  range_dir="source" ; cmd="ingress"
    elif [ "$2" = "OUT" ]; then range_dir="dest" ; cmd="egress" ;
    fi
    service_name=$(echo $rule_line | awk -F'\(|\ ' '{ print $2}')
    port=$(getent services ${service_name,,} | awk '{ print $2 }' | sed 's|\/.*||')
    proto=$(getent services ${service_name,,} | awk '{ print $2 }' | sed 's|.*\/||')
    ip_range=$(echo $rule_line | grep -oP "(?<=$range_dir )[^ ]*")
    aws ec2 authorize-security-group-${cmd} --group-id $sg_id --protocol $proto --port $port --cidr ${ip_range} --output json
}

secgroup_id=$(aws ec2 create-security-group \
--description "sec group for host $1" \
--group-name SecGroup$vm --output json | jq -r .GroupId)

#cat $path_to_rule_file
if [ -f $path_to_rule_file ]; then
	IFS=$'\r\n'
	for rule in $(sed -e '1,/RULES/d' $path_to_rule_file | grep -vE "DROP|REJECT" | sed 's/-log.*//g'); do
		if [[ $rule =~ "(" ]]; then
			gen_aws_command $rule $(echo $rule | awk '{print $1}') $secgroup_id
		fi
	done
else
	echo "There are no rules. Just create Sec Group!"
fi
