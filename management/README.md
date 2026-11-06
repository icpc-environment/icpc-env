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
   (the one images are built with), and `fleets_url` to where contestforge
   publishes `fleets.json`. Or `fleets_url: null` for static fleets only.
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

contestforge publishes to an R2 bucket served at
`https://configs.cloudcontest.org/v2/`: images' `config_url` (the default)
and wg-fleet's `fleets_url` both point there. Every file is signed, so the
bucket isn't trusted; wg-fleet checks `fleets.json` against `config_signers`
and keeps the last good copy if the bucket is unreachable.

The server can serve the files itself instead, e.g. for a test server
without the bucket: `https://<server>/configs/` serves `/srv/configs`, and
`fleets_url: "https://{{ external_hostname }}/configs/fleets.json"` reads
from there. contestforge publishes there as user `configs`, whose keys
(`configs_publisher_keys`) can only rsync into that directory:

```
just deploy   # in contestforge, writes instance/deployments
rsync -a --delete --delay-updates --exclude=.contestforge-cache \
  -e "ssh -i secrets/configs_publish" \
  instance/deployments/ configs@<server>:
```

`published_configs_dir` copies a local directory there on every deploy
instead.

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
* `/grafana/`: Grafana (same admin password), with Prometheus as its datasource.
  Its home page is the Contest overview dashboard (see Contest day)
* `/prometheus/`: Prometheus
* `/contestweb/`: anything written to `/srv/contestweb`

Released backups (`/b/`, see Backups) need no login: each link is its own
credential.

### Screenshots

`do-screenshots [fleet]` (as root) grabs every connected machine's screen and
writes a gallery to `/contestweb/screens/`.

### Backups

With `backup_enabled`, icpc-backupd backs up every connected machine built
with `remote_management_backup_enabled` (unless its site config turns
`backup.enabled` off) every `backup_interval_minutes`, into its own append-only
borg repo in `/srv/backups/<fleet>/<host>/`. It's pulled: the server forwards
a `borg serve` restricted to that repo over ssh (`-R`), and the machine's
`/icpc/scripts/icpc-backup run` sends it the contestant's home (no hidden
files, nothing over 1 MB, no build output) and icpc-printer's printouts. The
machine holds no credentials, and borg's cache there is in tmpfs, so backups
don't write to its drive.

Each backup also sends s.py's log of which window had focus as a separate
`focus-r<reset>-<time>` archive, and auditd's log of every program the
contestant ran as `exec-r<reset>-<time>` (both kept in tmpfs on the machine,
and wiped by a team reset). `release` only exports the team's files, never
these. To read one (`borg list` the repo for names; `ausearch` is in the
`auditd` package):

```
borg extract --stdout /srv/backups/<fleet>/<host>/repo::focus-...
cd $(mktemp -d) && borg extract /srv/backups/<fleet>/<host>/repo::exec-... \
  && ausearch --input var/log/audit -k contestant-exec -i
```

Images built with `remote_management_backup_app` give teams a Backups app on
their desktop: "Back up now", and up to three addresses to email a copy of
their files to after the contest, behind a privacy notice
(`remote_management_backup_contact` and
`remote_management_backup_retention_days` in the image's vars). Without it,
teams don't see backups at all, and you send them their links from your own
list of addresses.

```
backup-admin status [fleet]     # when each machine last backed up, what it left out
backup-admin now <fleet|host>   # back up now
```

At the end of the contest:

1. `backup-admin now <fleet>`, then `backup-admin status <fleet>` until every
   machine has backed up since the contest ended.
2. Once results are final, `backup-admin release <fleet>`. Each team's latest
   backup (since its machine's last team reset) becomes a tarball at an
   unguessable `https://<server>/b/<token>/...` link, and
   `/contestweb/backups/<fleet>.csv` lists every team with its link and the
   addresses it agreed to (`just mgmt backup-csv <fleet>`). Mail-merge from that.
3. Links, and the addresses, are deleted `backup_download_days` after release.
   `backup-admin purge <fleet> --yes` deletes the fleet's backups once you're done.

At most `backup_concurrency` machines back up at once, shared out evenly across
sites and at most `backup_site_concurrency` at one site, so a site's uplink
isn't hit by all its machines together. Machines without a site count by fleet.

Each fleet's interval (0 for only when asked) and upload rate limit can be
overridden in `backup_fleets`. The `backups` Prometheus job has each
machine's `icpc_backup_last_success_timestamp_seconds`.

### Last-minute ansible

Each team machine runs `local.yml` from its fleet's repo with ansible-pull
when it boots, and again when `/icpc/trigger-ansible` is created. The repo
starts out with a playbook that just records the applied revision in
`/icpc/update-version`.

Each fleet's user has a clone in `~/ansible-pull` that pushes without a
password:

```
ssh bigsouth2026-southeast@<server>
cd ~/ansible-pull
git pull            # someone else may have pushed
# edit local.yml, commit, push
```

From anywhere else, push over https with the admin password from
`secret.yml`:

```
git clone https://admin@<server>/git/bigsouth2026-southeast.git
```

Either way, machines pick it up at their next boot, or when root on the server
triggers them:

```
ansible bigsouth2026-southeast -b -m file -a 'path=/icpc/trigger-ansible state=touch'
```

The repos can be cloned without a password, since team machines pull them
anonymously. Don't put secrets in them.

### Contest day

`just contest` lists the day-of recipes: `health` (the server), `connected`,
`status` (a line per machine), `backups-online`, `printing`, `screenshots`,
`registered`, and `run <fleet> <command>` for anything else. `<fleet>` can also
be one machine, or `all`. Server times are UTC.

Grafana's Contest overview (`files/grafana/contest-overview.json`) shows the same
things by fleet and site. Set "Up longer than" to the time since you asked sites to
reboot, and machines that didn't are the ones over it. Image and applied revisions,
printouts since the last team reset and queued print jobs come from
`icpc-contest-metrics`. Images from before it was added get it from their fleet's
last-minute `local.yml`, so they only report them once they've applied that (Not
reporting details). Edits saved in Grafana last until that file
changes, so export them over it to keep them.

Reading what they show:

* A machine in a site fleet with a team hostname (`icpc-team-100`) got through
  setup. Only in `generic`, or named `icpc-<hex>`, it hasn't. `--2` on a
  hostname means another registration already had that name.
* Machines drop out of `connected` and `clients.db` when they stop pinging, so
  an empty list can just mean they're off. `backup-admin status` keeps every
  machine that has ever backed up, marked offline, test machines included.

Finding out who connected (`just contest registered "3 days ago"`, then `whois`
the source IPs on your own machine):

* Only registration shows a machine's real IP, in wg-fleet's journal and nginx's
  access log. Pings and git pulls come over the VPN, so they show `fd00:`
  addresses, and machines using wstunnel have a `127.0.0.1` wireguard endpoint.
* History is limited: nginx keeps about two weeks of logs, and `clients.db`
  only has machines connected now.
* The `site` a machine registers with is what its admin chose, not proof of
  where it is, so compare it with the source IP.

On the server:

* `wg show all dump` prints the interfaces' private keys. Use
  `wg show all endpoints` and `wg show all latest-handshakes`.
* There's no `sqlite3`. Read `/var/lib/wg-fleet/clients.db` with `python3`, and
  select columns, since it holds host certificates.
* Pass anything with quotes to `just mgmt ssh bash -s` on stdin, not as an
  argument: ssh joins the arguments and the remote shell parses them again.
