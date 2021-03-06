#!/bin/bash

#######################################################################
# INTERNATIONAL BUSINESS MACHINES CORPORATION PROVIDES THIS SOFTWARE ON
# AN "AS IS" BASIS AND IBM DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED,
# INCLUDING, BUT NOT LIMITED TO, THE WARRANTY OF NON-INFRINGEMENT AND THE
# IMPLIED WARRANTIES OF  MERCHANTABILITY OR FITNESS FOR A PARTICULAR
# PURPOSE.  IBM SHALL NOT BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR OPERATION OF
# THIS SOFTWARE.  IBM HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT,
# UPDATES, ENHANCEMENTS OR MODIFICATIONS TO THE SOFTWARE.
#######################################################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

remove_locks(){
  echo "====================="
  echo "Removing the locks"
  rm -f /var/lib/dpkg/lock
  rm -f /var/lib/apt/lists/lock
  rm -f /var/cache/apt/archives/lock
}

generate_ssh(){
  echo "====================="
  echo "Generating ssh keys"
  mkdir -p ${DIR}/keys_dir

  ssh-keygen -t rsa -f ${DIR}/keys_dir/ssh_key -P ''

}

copy_sshkey(){
  if [ ! -f ${DIR}/keys_dir/ssh_key.pub ]
  then
    generate_ssh
  fi
  cat ${DIR}/keys_dir/ssh_key.pub | ssh user1@$1 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
  ssh user1@$1 "echo $2 | sudo -S cp -r ~/.ssh /root/"
}

run_installer(){
  echo "====================="
  echo "Running the CfC installer"
  docker run -e LICENSE=accept --net=host --rm --entrypoint=cp \
             -v ${DIR}:/data ibmcom/cfc-installer:0.4.0 -r cluster /data
  cp ${DIR}/hosts ${DIR}/cluster/
  sed -i "s/network_type: flannel/network_type: calico/" ${DIR}/cluster/config.yaml
  echo "always_pull_images: false" >> ${DIR}/cluster/config.yaml
  cp keys_dir/ssh_key cluster/
  docker run -e LICENSE=accept --net=host --rm -t -v "$(pwd)/cluster":/installer/cluster ibmcom/cfc-installer:0.4.0 install
  mv ./kubectl /usr/local/bin/kubectl
}

#########################
# MAIN
#########################

LOCAL_IP=$(ip -o -4 addr list $(ip -o -4 route show to default | awk '{print $5}' | head -1) | awk '{print $4}' | cut -d/ -f1 | head -1)
PASSWORD=temp4Now

remove_locks
generate_ssh
##########
#TODO
#Key exchange should be done between the VMs so that
#a new key is used only to scramble the original key.

#$1 ip address
#$2 password
copy_sshkey ${LOCAL_IP} ${PASSWORD}
echo "[master]" > ${DIR}/hosts
echo "${LOCAL_IP}" >> ${DIR}/hosts
echo "" >> ${DIR}/hosts
echo "[worker]" >> ${DIR}/hosts
for ip in $(echo $1 | sed "s/,/ /g");
do
  copy_sshkey ${ip} ${PASSWORD}
  echo "${ip}" >> ${DIR}/hosts
done
echo "" >> ${DIR}/hosts
echo "[proxy]" >> ${DIR}/hosts
echo "${LOCAL_IP}" >> ${DIR}/hosts

run_installer
