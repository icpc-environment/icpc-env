# Management server

One server shared by every contest ("fleet"). Images built with
`remote_management_server` set connect to it to:

* join a WireGuard VPN, so admins can ssh to team machines and Prometheus can
  scrape them. Clients register with [wg-fleet](https://github.com/ubergeek42/wg-fleet),
  which hands out an address in their fleet's subnet. If UDP is blocked they
  fall back to wstunnel over `wss://<server>/wgtunnel/<port>`.
* fetch last-minute changes with ansible-pull from `https://<server>/git/<contest_id>.git`.

It runs wg-fleet (in podman), wstunnel, coredns, Prometheus, Grafana, and nginx.
nginx serves https and ssh on port 443, for networks that only allow 443 out.

## Deploying

1. Create an Ubuntu 26.04 droplet with your ssh key, and point a DNS name at it.
2. Put that name in `inventory.yml` (with the path to your key).
3. `cp secret.yml.example secret.yml` and set the admin password and each
   fleet's admin ssh keys.
4. Make sure `secrets/<mgmt_secrets_id>/` exists (`secrets/gen-secrets.sh generic`).
   Every fleet shares this set of keys, so build all images with
   `./fetch-secrets.sh` for the same id.
5. `just mgmt deploy`

Rerun `just mgmt deploy` after changing anything. It also pulls the latest
wg-fleet image and restarts wg-fleet if the image changed. `just mgmt check`
shows what would change, and `just mgmt ssh` / `just mgmt logs <unit>` help
with debugging.

### Adding a contest

Add an entry under `fleets` in `vars.yml` with a new subnet and port, and
deploy. The key must match the images' `contest_id`. This creates the
wireguard interface, a login user with the same name, and an empty
last-minute repo.

### Testing in a VM

With `-e letsencrypt_enabled=false` the playbook runs against any 26.04
machine, e.g. a local cloud-image VM, and nginx keeps a self-signed
certificate. Variables from `vars.yml` can only be overridden with `-e`, not
from the inventory.

## Using it

Log in as root or as your fleet's user (`ssh <fleet>@<server>`, or port 443).
Every admin account has the icpcadmin key and an ssh config that uses it.

Machines appear once they register a hostname, named
`<hostname>.<fleet>.icpcnet.internal`. On the server `t107.southeast` is enough:

```
ssh t107.southeast
cat /run/wg_fleet_hosts                       # everything currently connected
ansible southeast -m shell -a 'uptime'        # a whole fleet; inventory is /run/ansible_inventory.yml
ansible t107.southeast -b -m shell -a '/icpc/scripts/reset-team-account'
```

Machines that stop pinging wg-fleet for `fleet_timeout` are dropped.

### Web

Everything at `https://<server>/` needs the `admin` login from `secret.yml`.

* `/`: wg-fleet's dashboard of fleets and connected clients
* `/grafana/`: Grafana (same admin password), with Prometheus as its datasource
* `/prometheus/`: Prometheus
* `/contestweb/`: anything written to `/srv/contestweb`

### Screenshots

`do-screenshots [fleet]` (as root) grabs every connected machine's screen and
writes a gallery to `/contestweb/screens/`.

### Last-minute ansible

Each team machine runs `local.yml` from its fleet's repo with ansible-pull
when it boots, and again when `/icpc/trigger-ansible` is created. The repo
starts out with a playbook that just records the applied revision in
`/icpc/update-version`.

```
git clone https://admin@<server>/git/southeast.git
# edit local.yml, commit, push (password from secret.yml)
ansible southeast -b -m file -a 'path=/icpc/trigger-ansible state=touch'
```

The repos can be cloned without a password, since team machines pull them
anonymously. Don't put secrets in them.
