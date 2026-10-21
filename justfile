# Local settings, e.g. VM_ADMIN_SSH_KEY (see dev/README.md); modules see them too
set dotenv-load

mod vm 'dev/vm.just'
mod mgmt 'management/mgmt.just'
mod usb 'tools/usb/usb.just'
mod website 'website/website.just'

test:
    ./runvm.sh

baseimage:
    ./create_baseimg.sh

ssh:
    ssh -p 2222 -i ./configs/imageadmin-ssh_key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no imageadmin@localhost

dependencies:
    uv pip install -U -r requirements.txt
