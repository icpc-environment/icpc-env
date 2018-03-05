ssh host:
create keyfile
set up authorized_keys like so:
command="echo 'This account can only be used for opening a reverse tunnel.'",no-agent-forwarding,no-X11-forwarding ssh-ed25519 SSH_PUBKEY jumpy@ssh.yourserver.com


install parallel-ssh
create discover-hosts.sh file with contents:
PORTS=$(sudo lsof -i4TCP -sTCP:LISTEN -P -n | sed -r 's/.*:([0-9]+).*/\1/' | tail -n +2 )

for p in $PORTS; do
	# Skip localhost
	if [[ $p == 443 || $p == 22 ]]; then continue; fi
	TEAM=$(ssh localhost -p $p -i ~/.ssh/id_ed25519 -l root -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no cat /icpc/TEAM)
	echo "$TEAM - $p"
	cat >> ~/.ssh/config <<-EOF
	Host t$TEAM
		Hostname localhost
		Port $p
		User icpcadmin
		IdentityFile ~/.ssh/id_ed25519
	EOF
done




edit bashrc, add the following alias:

tssh ()
{
    SSTART=$1;
    shift;
    SEND=$1;
    shift;
    declare -a SERVERS;
    HOSTS=($(grep -w -i "Host" ~/.ssh/config | sed 's/Host//'));
    for i in $(seq $SSTART $SEND);
    do
        if [[ " ${HOSTS[@]} " =~ " t$(printf %03d $i) " ]]; then
            SERVERS+=("-H t$(printf "%03d" $i)");
        fi;
    done;
    echo -e "$ parallel-ssh \033[34m--timeout ${TIMEOUT:-10} --outdir /tmp/ \033[32m${SERVERS[@]} \033[31m$* \033[0m";
    read -n 1 -p "Run it? [${#SERVERS[@]} servers] " doit;
    echo;
    case $doit in
        y | Y)
            parallel-ssh -O StrictHostKeyChecking=no --timeout ${TIMEOUT:-10} --outdir /tmp/ ${SERVERS[@]} $*
        ;;
        *)
            return
        ;;
    esac
}


Run discover-hosts.sh once things are booted. Then you can use `tssh 0 100 command` to run a command across teams 0 to team 100.