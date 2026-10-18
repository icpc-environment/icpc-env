mod vm 'dev/vm.just'
mod mgmt 'management/mgmt.just'

test:
    ./runvm.sh

baseimage:
    ./create_baseimg.sh

ssh:
    ssh -p 2222 -i ./configs/imageadmin-ssh_key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no imageadmin@localhost

dependencies:
    uv pip install -U -r requirements.txt
