#!/bin/bash

## Variables
srcDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
key="basic_awscli_create_instance"
params=${srcDir}/${key}_params.json

## Functions
function get_instance_id(){
  grep -i instanceid ${params} | awk -F"\"" '{print $4}'
}

function get_instance_state(){
  aws ec2 describe-instances --instance-ids ${1} --query 'Reservations[].Instances[].State[].[Name]' --output text
}

function get_security_group_id(){
  grep -m 1 GroupId ${params} | awk -F"\"" '{print $4}' | sed '/^$/d'
}

function terminate_instances(){
  aws ec2 terminate-instances --instance-ids $(get_instance_id) >> /dev/null
}

function delete_key_pair(){
  aws ec2 delete-key-pair --key-name ${key}
  rm -f ${srcDir}/${key}.pem
}

function delete_security_group(){
  aws ec2 delete-security-group --group-id ${1}
}

function wait_for_instance_terminated(){
  while true; do
    until [ "$(get_instance_state ${1})" == 'terminated' ]; do
      sleep 1
      echo -e "\t\t\t\t$(get_instance_state ${1})"
    done
    break
  done
}

## BEGIN SCRIPT ##
# The following steps will restore back to a clean environment
echo -e "\t\tDeleting key pair..."
delete_key_pair
echo -e "\t\tTerminating instances..."
terminate_instances
echo -e "\t\t\tWaiting for instance to terminate..."
wait_for_instance_terminated $(get_instance_id)
echo -e "\t\tDeleting security group..."
delete_security_group $(get_security_group_id)
rm -f ${_srcDir}/${key}.pem ${params}
