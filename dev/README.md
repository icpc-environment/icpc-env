# Dev tooling

## `just vm` - scriptable VM harness

A non-interactive counterpart to `runvm.sh`. Every recipe returns once its work is done
and the VM keeps running in the background. That makes it usable from scripts and AI
agents as well as by hand. Run `just vm` to list the recipes.

```sh
just vm up                       # boot output/base-amd64.img (or `just vm up path/to/img`) and wait for ssh
just vm ansible                  # run main.yml (variant "generic"); only changed/failed tasks are shown
just vm ansible southeast --tags gui --start-at-task "..."   # variant + any ansible-playbook args
just vm reboot && just vm wait-desktop
just vm screenshot               # prints the path of a PNG of the screen
just vm click 700 450            # coordinates as seen in the screenshot
just vm key ctrl-alt-t           # key combos, using QEMU qcode names (ret, esc, tab, f1, meta_l, ...)
just vm type 'echo hi'
just vm ssh 'systemctl --failed' # as imageadmin; `admin` = icpcadmin, `gui` = desktop session user on :0
just vm cp somefile vm:/tmp/
just vm down                     # or `kill`, or `reset` to throw the disk away
```

### Getting past first-boot setup

After ansible and a reboot, the image shows its first-boot setup screen instead of the
contestant desktop, and `wait-desktop` says so. `just vm fake-setup` stands in for it: like
the wizard, it saves team 999 "ICPC Sysops Team" (ICPC Sysops) at site "sysops" in
`/icpc/config.json` and runs `/icpc/scripts/icpc-apply`, then reboots into the desktop, so
the wallpaper, panel and hostname show real team info. The team is set at the top of
`dev/fake-setup.py`. Ansible's `icpc` tag rewrites `/icpc/config.json` from group_vars,
which forgets the team again, so rerun `fake-setup` after it.

It also adds a printer that keeps every job instead of printing it. `just vm printouts`
copies those to `tmp/vm/$VM_NAME/printouts/`, with a PNG per page. With
`icpc_printer_enabled`, that printer is the real one behind icpc-printer, so the printouts
show its stamp (and cover page).

To try the real wizard instead, `just vm sample-configs` serves `dev/sample-configs/` (the
files contestforge publishes) inside the guest and points `config_url` at it. Then
`rm /icpc/setup-complete` and reboot. Contest `generic` has a plain site, an encrypted
one (passphrase `sample-passphrase`; it also sets the admin password hash, to `icpcadmin`
with a new salt) and a sysops site. The encrypted file was made with
`AGE_PASSPHRASE=sample-passphrase age -e -a -j batchpass`, as contestforge does.
The sites under "Broken" are ones the wizard must refuse: a file whose signature is
for another file, another site's config, and an expired one.

Every file has a `.sig` made with `dev/sample-signing-key`, a key for these samples
only (its private half is committed). `sample-configs` adds it to the guest's
`/etc/icpc/config-signers`, and `just vm ansible` builds with it in `config_signers`
(`dev/vm-vars.yml`). After editing a sample, rerun `dev/sign-sample-configs.sh`.

### State and checkpoints

Each VM lives in `tmp/vm/$VM_NAME/` (default `agent`). That directory holds a qcow2
overlay on top of the image it was first booted from, plus the pid, QMP socket, generated
ssh config, serial log, ansible log and screenshots. Changes persist across `down`/`up`
until `just vm reset`, which deletes the overlay. The base image is never modified.

`just vm checkpoint save|load|delete|list <name>` snapshots disk + RAM in a few seconds.

### Iterating on ansible

Each import in `main.yml` is tagged with its area (`gui`, `homedir`, `ca`, `reverseproxy`,
`compilers`, `devel_tools`, `icpc`, `vmtouch`, `network`, `system_restrictions`, `system`,
`ccs`, `management`). Two more tags cut across them:

- `slow`: the devdocs container build, about half of a full run.
- `lockdown`: `network` and `system_restrictions`. Once the firewall is up, rerunning
  other areas can fail (e.g. the vscode extension sync can't resolve DNS from podman).

Build a re-runnable base without those, checkpoint it, then iterate on top:

```sh
just vm reset && just vm up && just vm checkpoint save base-booted
just vm ansible --skip-tags slow,lockdown   # ~7.5 min vs ~17 for a full run
just vm checkpoint save fast
just vm ansible --tags gui                  # edit, rerun...
just vm checkpoint load fast                # ...or roll back and try again
just vm ansible                             # full run from base-booted before calling it done
```

`just vm timings` shows where the last run spent its time, per file and per task.

### Running several VMs

`VM_NAME`, `VM_SSHPORT` (default 2322), `VM_VNC` (display number, default 10 -> port 5910),
`VM_MEM` and `VM_CPUS` come from the environment. The defaults don't collide with
`runvm.sh` (2222 / :0). For a second VM:
`VM_NAME=other VM_SSHPORT=2323 VM_VNC=11 just vm up`.

Point a VNC viewer at `127.0.0.1:5910` to watch along.

### Notes

- The VM always boots EFI with secure boot, same as `runvm.sh`. The image must keep
  booting under BIOS too (`build-final.sh` and `test_final.sh` boot that way), but
  nothing here checks that yet.
- The serial log only captures firmware/GRUB output because the image doesn't put a
  kernel console on ttyS0. For boot failures, `screenshot` is more useful.
- `type` assumes a US keyboard layout in the guest.
- On final images only icpcadmin can log in; `wait-ssh` notices and `gui`/`reboot` use it.
  Their first-boot setup screen ignores the ACPI power button, so `down` waits out its
  timeout and then forces the VM off (`kill` skips the wait).
