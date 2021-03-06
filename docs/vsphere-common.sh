#!/bin/bash

if test -z "$BASH_VERSION"; then
  echo "Please run this script using bash, not sh or any other shell." >&2
  exit 1
fi

vsphere_install() {
  ### make temporary directory ###
  TMPDIR=/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
  mkdir -p ${TMPDIR}

  ### deb packages - mosh, OpenVPN, docker-compose ###
  echo "Installing deb packages..."
  sudo apt-get update
  sudo apt-get install -y mosh openvpn docker-compose

  ### vCenter CLI (govc) ###
  VERSION=$(curl -s https://api.github.com/repos/vmware/govmomi/releases/latest | jq -r .tag_name)
  pushd ${TMPDIR}
    curl -LO https://github.com/vmware/govmomi/releases/download/v0.23.0/govc_linux_amd64.gz
    gunzip govc_linux_amd64.gz
    sudo install -m 755 ./govc_linux_amd64 /usr/local/bin/govc
  popd

  ### My VMware CLI (vmw-cli) ###
  # see: https://github.com/apnex/vmw-cli
  sudo docker run apnex/vmw-cli shell > ${TMPDIR}/vmw-cli
  sudo install -m 755 ${TMPDIR}/vmw-cli /usr/local/bin/

  ### remove temporary directory ###
  rm -rf ${TMPDIR}
}

vsphere_setup_homedir() {
  ### SSH via key ###
  if [ ! -f $HOME/.ssh/authorized_keys ] || ! grep -q ssh-import-id $HOME/.ssh/authorized_keys ; then
    github_id="${GITHUB_ID:-kenojiri}"
    echo "Installing SSH public key..."
    ssh-import-id-gh $github_id
  fi

  ### workspace directory ###
  mkdir -p $HOME/workspace/scripts
  cat <<EOF > $HOME/workspace/scripts/env-tkgimc.sh
export OM_HOSTNAME=\$(curl -sk -u "root:\${TKGIMC_PASSWORD}" https://\${TKGIMC_HOST}/api/deployment/environment | jq -r '.[] | select(.key == "network.opsman_reachable_ip") | .value')
export OM_USERNAME=admin
export OM_PASSWORD=\$(curl -sk -u "root:\${TKGIMC_PASSWORD}" https://\${TKGIMC_HOST}/api/deployment/environment | jq -r '.[] | select(.key == "opsman.admin_password") | .value')
export OM_DECRYPTION_PASSPHRASE=\${OM_PASSWORD}
export OM_TARGET="https://\${OM_HOSTNAME}"
export OM_SKIP_SSL_VALIDATION="true"

curl -sk -u "root:\${TKGIMC_PASSWORD}" https://\${TKGIMC_HOST}/api/deployment/environment | jq -r '.[] | select(.key == "opsman.ssh_private_key") | .value' > \${OM_SSHKEY_FILEPATH}
chmod 600 \${OM_SSHKEY_FILEPATH}
export BOSH_ALL_PROXY="ssh+socks5://ubuntu@\${OM_HOSTNAME}:22?private-key=\${OM_SSHKEY_FILEPATH}"
eval "\$(om bosh-env)"
EOF
}
