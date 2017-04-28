#!/bin/bash

## Variables
hvm_amzn_ami="ami-8ca83fec"
hvm_rhel_ami="ami-6f68cf0f"
hvm_suse_ami="ami-e4a30084"
hvm_ubun16_ami="ami-efd0428f"
hvm_ubun14_ami="ami-7c22b41c"
pv_amzn_ami="ami-7453c414"
pv_suse_ami="ami-baab0fda"

region="us-west-2"
instance_type="t2.micro"
srcDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
key="basic_awscli_create_instance"
params=${srcDir}/${key}_params.json
wait_seconds="3"

## Functions
function create_security_group(){
  security_group_id=$(aws ec2 create-security-group --group-name ${key} --description "${key} Security Group SSH Access" --output text)
}

function security_group_allow_ssh(){
  aws ec2 authorize-security-group-ingress --port 22 --protocol tcp --group-id ${security_group_id} --cidr 0.0.0.0/0
}

function get_instance_id(){
  grep -i instanceid ${params} | awk -F"\"" '{print $4}'
}

function create_key_pair(){
  aws ec2 create-key-pair --key-name ${key} >> ${params}
  grep KeyMaterial ${params} | awk -F"\"" '{print $4}' | awk '{gsub(/\\n/,"\n")}1' > ${srcDir}/${key}.pem
  chmod 400 ${srcDir}/${key}.pem
}

function tag_resources(){
  aws ec2 create-tags --resources ${instance_id} ${security_group_id} --tags Key=Name,Value=${key}
}

function run_instance(){
  aws ec2 run-instances \
  --region ${region} \
  --image-id ${ami_id} \
  --key-name ${key} \
  --security-group-ids ${security_group_id} \
  --instance-type ${instance_type} \
  --count 1 >> ${params}
}

function get_instance_state(){
  aws ec2 describe-instances --instance-ids ${instance_id} --query 'Reservations[].Instances[].State[].[Name]' --output text
}

function get_instance_public_dns(){
  aws ec2 describe-instances --instance-ids ${instance_id} --query 'Reservations[].Instances[].[PublicDnsName]' --output text
}

function wait_for_instance_state(){
  echo -e "\n\t- Waiting for Instance [${instance_id}] State to be running"
  while true; do
    until [ "${v_instance_state}" == "${1}" ]; do
      sleep ${wait_seconds}
      local v_instance_state=$(get_instance_state ${2})
    done
    break
  done
  echo -e "\t- Instance [${instance_id}] is running\n"
}

function test_ssh(){
  exec 3>&2
  exec 2> /dev/null
  ssh -i ${srcDir}/${key}.pem -o "StrictHostKeyChecking no" ${ssh_user}@$(get_instance_public_dns $(get_instance_id)) echo ""
  if [ $? -eq 0 ]; then
    _ssh_availability=1
    echo -e "\t- SSH available, opening socket\n"
  else
    _ssh_availability=0
    echo -e "\t- SSH availability pending..."
  fi
  exec 2>&3
}

function wait_for_ssh(){
  while true; do
    until [[ $_ssh_availability -eq 1 ]]; do
      sleep ${wait_seconds}
      test_ssh
    done
    break
  done
}

function ssh_to_instance(){
  ssh -i ${srcDir}/${key}.pem -o "StrictHostKeyChecking no" ${ssh_user}@$(get_instance_public_dns $(get_instance_id))
}

function menu(){
  echo -e "\nPlease select which AMI you would like to use from the list below\n
  \t1 Amazon Linux AMI 2017.03.0 (HVM), SSD Volume Type - ${hvm_amzn_ami}
  \t2 Red Hat Enterprise Linux 7.3 (HVM), SSD Volume Type - ${hvm_rhel_ami}
  \t3 SUSE Linux Enterprise Server 12 SP2 (HVM), SSD Volume Type - ${hvm_suse_ami}
  \t4 Ubuntu Server 16.04 LTS (HVM), SSD Volume Type - ${hvm_ubun16_ami}
  \t5 Amazon Linux AMI 2017.03.0 (PV) - ${pv_amzn_ami}
  \t6 Ubuntu Server 14.04 LTS (HVM), SSD Volume Type - ${hvm_ubun14_ami}
  \t7 SUSE Linux Enterprise Server 11 SP4 (PV), SSD Volume Type - ${pv_suse_ami}
  \t8 Quit\n"
}

## BEGIN SCRIPT ##
for file in ${params} ${key}.pem; do
  if [ -e ${file} ]; then rm -f ${params}; fi
done
menu
read -p "Selection: " choice

while true; do
  case $choice in
    1) ssh_user="ec2-user"; ami_id=${hvm_amzn_ami}; break
    ;;
    2) ssh_user="ec2-user"; ami_id=${hvm_rhel_ami}; break
    ;;
    3) ssh_user="ec2-user"; ami_id=${hvm_suse_ami}; break
    ;;
    4) ssh_user="ubuntu"; ami_id=${hvm_ubun16_ami}; break
    ;;
    5) ssh_user="ec2-user"; ami_id=${pv_amzn_ami}; break
    ;;
    6) ssh_user="ubuntu"; ami_id=${hvm_ubun14_ami}; break
    ;;
    7) ssh_user="ec2-user"; ami_id=${pv_suse_ami}; break
    ;;
    8) exit 0
    ;;
    *) clear;echo -e "Invalid selection!\n"; menu; read -p "Selection: " choice
    ;;
  esac
done

create_security_group
echo -e "\n\t- Security Group [${security_group_id}] Created"
security_group_allow_ssh
echo -e "\t- Authorizing SSH Ingress in Security Group [${security_group_id}]"
create_key_pair
echo -e "\t- Created Key Pair [${key}.pem]"
chmod 600 ./${key}.pem
run_instance
instance_id=$(get_instance_id)
wait_for_instance_state "running"
tag_resources
echo -e "\t- Tagging Resources [${instance_id}, ${security_group_id}]\n"

read -p "Would you like to ssh to \"${instance_id}\" right now? [Y/n]: " yesorno
while true; do
  case $yesorno in
    [Yy]* )
      wait_for_ssh
      ssh_to_instance
      break
    ;;
    [Nn]* )
      echo -e "\tIf you change your mind, you can access instance [${instance_id}] via;\n"
      echo -e "ssh -i ${srcDir}/${key}.pem ${ssh_user}@$(get_instance_public_dns $(get_instance_id))"
      break
    ;;
    * ) read -p "Invalid Input, please answer [Y/n]: " yesorno ;;
  esac
done

exit 0
## END SCRIPT ##
