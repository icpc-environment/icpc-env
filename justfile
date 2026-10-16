mod vm 'dev/vm.just'
mod mgmt 'management/mgmt.just'

test:
    ./runvm.sh

baseimage:
    ./create_baseimg.sh

ssh:
    ssh -p 2222 -i ./configs/imageadmin-ssh_key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no imageadmin@localhost

# Create the ssh CA and keys for a contest in secrets/<contest_id>
keys contest_id="generic":
    secrets/make-keys.sh {{contest_id}}

dependencies:
    uv pip install -U -r requirements.txt
