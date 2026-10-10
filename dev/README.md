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

### State and checkpoints

Each VM lives in `tmp/vm/$VM_NAME/` (default `agent`). That directory holds a qcow2
overlay on top of the image it was first booted from, plus the pid, QMP socket, generated
ssh config, serial log, ansible log and screenshots. Changes persist across `down`/`up`
until `just vm reset`, which deletes the overlay. The base image is never modified.

`just vm checkpoint save|load|delete|list <name>` snapshots disk + RAM in a few seconds.
The usual loop for iterating on a role is:

```sh
just vm up && just vm checkpoint save fresh
just vm ansible --tags whatever      # edit, rerun...
just vm checkpoint load fresh        # ...and roll back to try again from scratch
```

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
