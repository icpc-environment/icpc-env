# Use when running create_baseimage.sh to log in to the installer environment (in case there are issues)
ssh:
		ssh -p 2222 -i ./configs/imageadmin-ssh_key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no imageadmin@localhost


# use when running create_baseimage.sh to monitor the progress of the install
monitor_install:
		ssh -p 5222 -i ./configs/imageadmin-ssh_key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no installer@localhost

# Use when running create_baseimage.sh to log in to the installer environment (in case there are issues)
login_install:
		ssh -p 5222 -i ./configs/imageadmin-ssh_key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no imageadmin@localhost

test_ssh:
		ssh -p 2222 -i files/secrets/icpcadmin@contestmanager -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no icpcadmin@localhost


download_configs:
	aws s3 sync s3://configs.cloudcontest.org/ printer-configs/
upload_configs:
	aws s3 sync --delete printer-configs/ s3://configs.cloudcontest.org/

ansible:
	bash -c 'ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i tmp_inventory --diff --become -u imageadmin --private-key "${PWD}/configs/imageadmin-ssh_key" --ssh-extra-args="-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" main.yml'
