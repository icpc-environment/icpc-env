# Management server

One server shared by every contest ("fleet"). Images built with
`remote_management_server` set, and machines whose site config names it,
connect to it to:

* join a WireGuard VPN, so admins can ssh to team machines and Prometheus can
  scrape them. Clients register with [wg-fleet](https://github.com/ubergeek42/wg-fleet),
  which hands out an address in their fleet's subnet. If UDP is blocked they
  fall back to wstunnel over `wss://<server>/wgtunnel/<port>`.
* fetch last-minute changes with ansible-pull from `https://<server>/git/<fleet>.git`.

Most fleets come from contestforge: wg-fleet reads its signed `fleets.json`
from `fleets_url` and picks up new ones without a deploy, and their machines
register with their site's enrollment token. The static `fleets` in
`vars.yml` take anyone: the setup fleet images join before setup (named after
their `contest_id`), and contests not managed in contestforge. Machines move
from the setup fleet to their site's fleet once setup has run.

It runs wg-fleet (in podman), wstunnel, coredns, Prometheus, Grafana, and nginx.
nginx serves https and ssh on port 443, for networks that only allow 443 out.

## Deploying

1. Create an Ubuntu 26.04 droplet with your ssh key, and point a DNS name at it.
2. Put that name in `inventory.yml` (with the path to your key).
3. `cp secret.yml.example secret.yml` and set the admin password, and any
   plain ssh keys for static fleets' users.
4. Set `config_signers` in `vars.yml` to contestforge's allowed_signers line
   (the one images are built with), and `configs_publisher_keys` to the ssh
   key contestforge publishes with. Or `fleets_url: null` for static fleets
   only.
5. `just mgmt deploy`
6. Get the server's own key a certificate, so root can reach team machines:
   the deploy copies it to `secrets/mgmt/<server>/id_ed25519.pub`. In
   contestforge, `flask ssh-cert sign --server <server> --pubkey <that file>`,
   save the result as `secrets/mgmt/<server>/id_ed25519-cert.pub` and deploy
   again.
7. Give contestforge the server's host CA (`secrets/mgmt/<server>/host_ca.pub`,
   or `https://<server>/ssh/host_ca.pub`) for its configs' `ssh_host_ca_keys`:
   `flask mgmt-server set-host-ca <server> <file>`, then publish.

The deploy backs wg-fleet's host CA up to `secrets/mgmt/<server>/` and
restores it from there onto a rebuilt server. Keep that directory: every
machine's host certificate and every admin's known_hosts depend on it.
Keys made elsewhere can be put there before the first deploy instead
(`host_ca`, and the server's `id_ed25519` with its certificate).

Rerun `just mgmt deploy` after changing anything. It also pulls the latest
wg-fleet image and restarts wg-fleet if the image changed. `just mgmt check`
shows what would change, and `just mgmt ssh` / `just mgmt logs <unit>` help
with debugging.

### Adding a contest

Enable remote management for the contest in contestforge and publish. Within
wg-fleet's refresh interval it creates the fleet's wireguard interface, and
fleet-sync (run whenever wg-fleet's list of fleets changes) creates a login
user with the fleet's name, its last-minute repo and its wstunnel server.

A static fleet is an entry under `fleets` in `vars.yml` with a new subnet and
port, and a deploy. A fleet that goes away keeps its user and repo, but its
user can't log in with a certificate or reach any machine any more.

### Testing in a VM

With `-e letsencrypt_enabled=false` the playbook runs against any 26.04
machine, e.g. a local cloud-image VM, and nginx keeps a self-signed
certificate. Variables from `vars.yml` can only be overridden with `-e`, not
from the inventory.

### Published files

The server is also where images' `config_url` and wg-fleet's `fleets_url`
point: `https://<server>/configs/` serves `/srv/configs`. contestforge
publishes there as user `configs`, whose keys (`configs_publisher_keys`) can
only rsync into that directory:

```
just deploy   # in contestforge, writes instance/deployments
rsync -a --delete --delay-updates --exclude=.contestforge-cache \
  -e "ssh -i secrets/configs_publish" \
  instance/deployments/ configs@<server>:
```

`published_configs_dir` copies a local directory there on every deploy
instead, e.g. for a test server.

## Using it

Admins log in to team machines as icpcadmin with a certificate from
contestforge (`flask ssh-cert sign`), whose principals say which contests'
machines it opens. Jump through your fleet's user, which holds no keys and can
only reach that fleet's machines:

```
ssh -J <fleet>@<server> icpcadmin@t107.<fleet>.icpcnet.internal
```

Port 443 works too (`-J <fleet>@<server>:443`). Global admins (`node:*`) can
also use the setup fleet's user.

On the server, root uses the server's own certified key. Machines appear once
they register a hostname, named `<hostname>.<fleet>.icpcnet.internal`, and
`t107.bigsouth2026-southeast` is enough:

```
ssh t107.bigsouth2026-southeast
cat /run/wg_fleet_hosts                       # everything currently connected
ansible bigsouth2026-southeast -m shell -a 'uptime'        # a whole fleet; inventory is /run/ansible_inventory.yml
ansible t107.bigsouth2026-southeast.icpcnet.internal -b -m shell -a '/icpc/scripts/reset-team-account'
```

Machines in fleets from contestforge have host certificates from wg-fleet's
host CA, which the server trusts for `*.icpcnet.internal`. Put the same line
in your own known_hosts:

```
@cert-authority *.icpcnet.internal <contents of https://<server>/ssh/host_ca.pub>
```

Machines in static fleets (the setup fleet) have no certificate. ssh on the
server accepts their keys the first time and keeps them in
`~/.ssh/known_hosts.<fleet>`. To do the same through the bastion:

```
Host *.<fleet>.icpcnet.internal
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts.<fleet>
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
git clone https://admin@<server>/git/bigsouth2026-southeast.git
# edit local.yml, commit, push (password from secret.yml)
ansible bigsouth2026-southeast -b -m file -a 'path=/icpc/trigger-ansible state=touch'
```

The repos can be cloned without a password, since team machines pull them
anonymously. Don't put secrets in them.
