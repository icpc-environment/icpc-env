# Non-interactive VM harness, run as `just vm <recipe>` from the repo root.
# Each recipe returns once its work is done and the VM keeps running in the
# background. See dev/README.md for the iterate loop.

set working-directory := '..'
set positional-arguments
set shell := ['bash', '-cu']

root := parent_directory(source_directory())
qmp := "python3 " + source_directory() / "qmp.py"

# Instance settings, overridable from the environment so several VMs can run side by side
export VM_NAME := env("VM_NAME", "agent")
export VM_SSHPORT := env("VM_SSHPORT", "2322")
export VM_VNC := env("VM_VNC", "10")
export VM_MEM := env("VM_MEM", "6144")
export VM_CPUS := env("VM_CPUS", "4")

export VM_STATE := root / "tmp/vm" / VM_NAME
export QMP_SOCK := VM_STATE / "qmp.sock"
ssh := "ssh -F " + VM_STATE / "ssh_config"
# Whichever sudo-capable account answered in wait-ssh: imageadmin, or icpcadmin on final images
sudo_host := '"$(cat ' + VM_STATE / 'sudo_host 2>/dev/null || echo vm)"'

[private]
default:
    @just --list vm

# Boot the VM and wait for ssh. The first boot creates a qcow2 overlay on `image`; later boots reuse it until `reset`
up image="" timeout="600": && (wait-ssh timeout)
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "$VM_STATE/qemu.pid" ] && kill -0 "$(cat "$VM_STATE/qemu.pid")" 2>/dev/null; then
      echo "$VM_NAME is already running"
      exit 0
    fi
    mkdir -p tmp/vm
    chattr +C tmp/vm 2>/dev/null || true
    mkdir -p "$VM_STATE/screenshots"
    ovmf=$(dev/ovmf.sh)
    read -r ovmf_code ovmf_vars <<<"$ovmf"
    if [ ! -f "$VM_STATE/disk.qcow2" ]; then
      img=$(realpath "${1:-output/base-amd64.img}")
      fmt=$(qemu-img info --output=json "$img" | jq -r .format)
      echo "Creating overlay on $img ($fmt)"
      qemu-img create -q -f qcow2 -b "$img" -F "$fmt" "$VM_STATE/disk.qcow2"
      # qcow2 rather than raw so `checkpoint save` can snapshot the EFI vars too
      qemu-img convert -O qcow2 "$ovmf_vars" "$VM_STATE/vars.qcow2"
      echo "$img" > "$VM_STATE/image"
    elif [ -n "$1" ] && [ "$(realpath "$1")" != "$(cat "$VM_STATE/image")" ]; then
      echo "error: $VM_NAME's overlay is based on $(cat "$VM_STATE/image"), run 'just vm reset' to switch images" >&2
      exit 1
    fi

    # Cloud builders often have no /dev/kvm, where --enable-kvm is fatal rather than slow
    if [ -r /dev/kvm ]; then
      ACCEL=(--enable-kvm -cpu host)
    else
      echo "No /dev/kvm - falling back to emulation, this will be slow"
      ACCEL=(-cpu max)
    fi

    chmod 0400 configs/imageadmin-ssh_key
    [ -L "$VM_STATE/secrets" ] || ln -sfn "$(dirname "$(secrets/admin-key.sh)")" "$VM_STATE/secrets"
    cat > "$VM_STATE/ssh_config" <<EOF
    Host vm
      User imageadmin
      IdentityFile {{root}}/configs/imageadmin-ssh_key
    Host vm-admin
      User icpcadmin
      IdentityFile $VM_STATE/secrets/icpcadmin@contestmanager
    Host *
      HostName 127.0.0.1
      Port $VM_SSHPORT
      IdentitiesOnly yes
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR
      BatchMode yes
      ConnectTimeout 5
      ServerAliveInterval 5
      ServerAliveCountMax 2
      ControlMaster auto
      ControlPath $VM_STATE/ssh-%r.sock
      ControlPersist 10m
    EOF

    rm -f "$VM_STATE/serial.log"
    qemu-system-x86_64 -name "icpc-$VM_NAME" -machine q35,smm=on "${ACCEL[@]}" -smp "$VM_CPUS" -m "$VM_MEM" \
      -global driver=cfi.pflash01,property=secure,value=on \
      -drive if=pflash,format=raw,unit=0,file="$ovmf_code",readonly=on \
      -drive if=pflash,format=qcow2,unit=1,file="$VM_STATE/vars.qcow2",cache=unsafe \
      -drive file="$VM_STATE/disk.qcow2",index=0,media=disk,format=qcow2,cache=unsafe \
      -net user,hostfwd=tcp:127.0.0.1:"$VM_SSHPORT"-:22 -net nic \
      -vnc 127.0.0.1:"$VM_VNC" -device VGA,edid=on,xres=1440,yres=900 -usbdevice tablet \
      -qmp unix:"$QMP_SOCK",server=on,wait=off \
      -serial file:"$VM_STATE/serial.log" \
      --daemonize --pidfile "$VM_STATE/qemu.pid"
    echo "Started $VM_NAME: ssh port $VM_SSHPORT, vnc 127.0.0.1:$((5900 + VM_VNC))"

# Wait until ssh answers as imageadmin or icpcadmin, failing early if qemu dies
wait-ssh timeout="600":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Waiting up to $1s for ssh on port $VM_SSHPORT"
    deadline=$((SECONDS + $1))
    while true; do
      for host in vm vm-admin; do
        if {{ssh}} -S none -o ConnectTimeout=2 "$host" true 2>/dev/null; then
          echo "$host" > "$VM_STATE/sudo_host"
          echo "ssh is up ($host)"
          exit 0
        fi
      done
      if ! kill -0 "$(cat "$VM_STATE/qemu.pid" 2>/dev/null)" 2>/dev/null; then
        echo "error: qemu is not running" >&2
        exit 1
      fi
      if (( SECONDS >= deadline )); then
        echo "error: timed out waiting for ssh, try 'just vm screenshot' or 'just vm console'" >&2
        exit 1
      fi
      sleep 2
    done

# Wait until an XFCE session is running (only exists once ansible has run)
wait-desktop timeout="180":
    #!/usr/bin/env bash
    set -euo pipefail
    deadline=$((SECONDS + $1))
    until owner=$({{ssh}} {{sudo_host}} ps -o user= -C xfce4-session 2>/dev/null) && [ -n "$owner" ]; do
      if (( SECONDS >= deadline )); then
        echo "error: timed out waiting for the contestant desktop" >&2
        exit 1
      fi
      sleep 2
    done
    if [ "$owner" = root ]; then
      echo "error: the first-boot setup screen is up, not the contestant desktop. To skip it:" >&2
      echo "  just vm fake-setup" >&2
      exit 1
    fi
    # Give the panel and wallpaper a moment to draw before anyone screenshots it
    sleep 3
    echo "desktop is up"

# Ask the guest to shut down (ACPI power button), forcing it off after `timeout` seconds
down timeout="60":
    #!/usr/bin/env bash
    set -euo pipefail
    pid=$(cat "$VM_STATE/qemu.pid" 2>/dev/null || true)
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      echo "$VM_NAME is not running"
      exit 0
    fi
    {{qmp}} raw '{"execute": "system_powerdown"}' >/dev/null
    deadline=$((SECONDS + $1))
    while kill -0 "$pid" 2>/dev/null; do
      if (( SECONDS >= deadline )); then
        echo "Guest didn't power off within $1s, forcing it"
        kill "$pid"
        break
      fi
      sleep 1
    done
    rm -f "$VM_STATE/qemu.pid"
    echo "$VM_NAME stopped"

# Force the VM off immediately
kill:
    #!/usr/bin/env bash
    pid=$(cat "$VM_STATE/qemu.pid" 2>/dev/null || true)
    if [ -n "$pid" ] && kill "$pid" 2>/dev/null; then
      tail --pid="$pid" -f /dev/null
      echo "$VM_NAME killed"
    fi
    rm -f "$VM_STATE/qemu.pid"

# Kill the VM and delete its overlay, so the next `up` starts from a clean image
reset: kill
    @rm -rf "$VM_STATE"
    @echo "$VM_NAME reset"

# Show whether the VM is running, what it was booted from and whether ssh answers
status:
    #!/usr/bin/env bash
    echo "name:   $VM_NAME ($VM_STATE)"
    echo "image:  $(cat "$VM_STATE/image" 2>/dev/null || echo '(no overlay yet)')"
    pid=$(cat "$VM_STATE/qemu.pid" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "qemu:   running (pid $pid), ssh port $VM_SSHPORT, vnc 127.0.0.1:$((5900 + VM_VNC))"
      for host in vm vm-admin; do
        if {{ssh}} -S none -o ConnectTimeout=2 "$host" true 2>/dev/null; then echo "ssh:    up ($host)"; break; fi
        [ "$host" = vm-admin ] && echo "ssh:    down"
      done
    else
      echo "qemu:   stopped"
    fi

# Run a command as imageadmin (no command: interactive shell)
ssh *cmd:
    @{{ssh}} vm "$@"

# Run a command as icpcadmin, the account the final image keeps (no command: interactive shell)
admin *cmd:
    @{{ssh}} vm-admin "$@"

# Run a shell command as the desktop session's user (normally contestant) in its environment, e.g. `just vm gui 'xfce4-terminal &'`
gui *cmd:
    #!/usr/bin/env bash
    {{ssh}} {{sudo_host}} bash -s -- "$(printf %q "$*")" <<'EOF'
    pid=$(pgrep -o -x xfce4-session) || { echo "error: no desktop session running" >&2; exit 1; }
    mapfile -t session_env < <(sudo cat /proc/$pid/environ | tr '\0' '\n' |
      grep -E '^(DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|HOME)=')
    sudo -u "$(ps -o user= -p "$pid")" env "${session_env[@]}" bash -c "cd ~ && $1" </dev/null
    EOF

# Copy files with scp, prefixing guest paths with `vm:` (or `vm-admin:`)
cp +args:
    @scp -F "$VM_STATE/ssh_config" -r "$@"

# Run main.yml against the VM. Optional first arg is the variant group (default generic), the rest go to ansible-playbook
ansible *args:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=generic
    if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
      variant=$1
      shift
    fi
    cat > "$VM_STATE/inventory" <<EOF
    vm ansible_port=$VM_SSHPORT ansible_host=127.0.0.1
    [$variant]
    vm
    EOF
    ln -sfn "$(dirname "$(secrets/admin-key.sh "$variant")")" "$VM_STATE/secrets"
    for f in ansible.log timing.jsonl; do
      [ -f "$VM_STATE/$f" ] && mv "$VM_STATE/$f" "$VM_STATE/$f.prev"
    done
    ansible_playbook=ansible-playbook
    [ -x .venv/bin/ansible-playbook ] && ansible_playbook=.venv/bin/ansible-playbook
    echo "Running ansible (variant $variant), log in $VM_STATE/ansible.log"
    # Only changed/failed tasks are shown by default, set ANSIBLE_DISPLAY_OK_HOSTS=true to see everything
    ANSIBLE_HOST_KEY_CHECKING=False \
    ANSIBLE_DISPLAY_OK_HOSTS="${ANSIBLE_DISPLAY_OK_HOSTS:-false}" \
    ANSIBLE_DISPLAY_SKIPPED_HOSTS="${ANSIBLE_DISPLAY_SKIPPED_HOSTS:-false}" \
    ANSIBLE_CALLBACK_RESULT_FORMAT="${ANSIBLE_CALLBACK_RESULT_FORMAT:-yaml}" \
    ANSIBLE_LOG_PATH="$VM_STATE/ansible.log" \
    ANSIBLE_CALLBACK_PLUGINS="{{source_directory()}}/callback_plugins" \
    ANSIBLE_CALLBACKS_ENABLED=timing \
    VM_TIMING_LOG="$VM_STATE/timing.jsonl" \
      "$ansible_playbook" -i "$VM_STATE/inventory" --diff --become -u imageadmin --private-key configs/imageadmin-ssh_key \
      --ssh-extra-args="-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
      main.yml "$@"

# Summarise per-task timings from the last `ansible` run (or the one before it with `prev=.prev`)
timings top="25" prev="":
    @python3 {{source_directory()}}/timings.py "$VM_STATE/timing.jsonl$2" "$1"

# Get past the first-boot setup screen as a made up team (see dev/fake-setup.py), then reboot into the desktop
fake-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(cat "$VM_STATE/sudo_host" 2>/dev/null || echo vm)
    scp -F "$VM_STATE/ssh_config" -q {{source_directory()}}/fake-setup.py "$host":/tmp/fake-setup.py
    {{ssh}} "$host" sudo python3 /tmp/fake-setup.py
    just vm reboot
    just vm wait-desktop

# Copy what's been printed to the fake printer into tmp/vm/<name>/printouts/, with a PNG per page
printouts:
    #!/usr/bin/env bash
    set -euo pipefail
    out="$VM_STATE/printouts"
    mkdir -p "$out"
    {{ssh}} {{sudo_host}} 'sudo tar -C /var/lib/fake-printer -cf - --exclude="*.png" .' | tar -C "$out" -xf -
    for pdf in "$out"/*.pdf; do
      [ -e "$pdf" ] || { echo "nothing printed yet"; exit 0; }
      [ -e "${pdf%.pdf}-1.png" ] || pdftoppm -png -r 80 "$pdf" "${pdf%.pdf}"
      ls "${pdf%.pdf}"*.png
    done

# Launch, screenshot and close each desktop tool, then hello-world each language (or just the named ones, incl. `languages`)
smoke *tools:
    @{{source_directory()}}/smoke.sh "$@"

# Reboot the guest and wait for ssh to come back
reboot timeout="600":
    #!/usr/bin/env bash
    set -euo pipefail
    {{ssh}} {{sudo_host}} sudo systemctl reboot || true
    {{ssh}} -O exit vm 2>/dev/null || true
    {{ssh}} -O exit vm-admin 2>/dev/null || true
    # Give it time to actually go down so we don't ssh straight back into the old boot
    sleep 5
    just vm wait-ssh "$1"

# Save a PNG of the screen (default tmp/vm/<name>/screenshots/<time>.png) and print its path
screenshot out="":
    #!/usr/bin/env bash
    set -euo pipefail
    {{qmp}} screenshot "${1:-$VM_STATE/screenshots/$(date +%Y%m%d-%H%M%S).png}"

# Press key combos in order, e.g. `just vm key ctrl-alt-t` or `just vm key alt-f4 ret`
key +combos:
    @{{qmp}} key "$@"

# Type text with a US keyboard layout
type +text:
    @{{qmp}} type "$@"

# Click at screen coordinates (as seen in a screenshot), e.g. `just vm click 700 450 right` or `... left --double`
click x y *opts:
    @{{qmp}} click "$@"

# Move the pointer to screen coordinates without clicking
move x y:
    @{{qmp}} move "$@"

# Scroll the mouse wheel up or down
scroll direction count="3":
    @{{qmp}} scroll "$@"

# Show the last lines of the serial console log
console lines="50":
    @tail -n "$1" "$VM_STATE/serial.log"

# Save, load, delete or list VM snapshots (disk + RAM), e.g. `just vm checkpoint save post-ansible`
checkpoint action name="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "$1" in
      save|load|delete)
        [ -n "$2" ] || { echo "error: checkpoint $1 needs a name" >&2; exit 1; }
        cmd=$(case "$1" in save) echo savevm;; load) echo loadvm;; delete) echo delvm;; esac)
        {{qmp}} hmp "$cmd" "$2"
        if [ "$1" = load ]; then
          # The guest just jumped in time, so any multiplexed ssh connection is dead
          {{ssh}} -O exit vm 2>/dev/null || true
          {{ssh}} -O exit vm-admin 2>/dev/null || true
        fi
        echo "checkpoint $1 $2: done"
        ;;
      list)
        if [ -S "$QMP_SOCK" ] && kill -0 "$(cat "$VM_STATE/qemu.pid" 2>/dev/null)" 2>/dev/null; then
          {{qmp}} hmp info snapshots
        else
          qemu-img snapshot -l "$VM_STATE/disk.qcow2"
        fi
        ;;
      *)
        echo "error: action must be save, load, delete or list" >&2
        exit 1
        ;;
    esac

# Send a raw QMP command (JSON) or a human monitor command, e.g. `just vm qmp info status`
qmp +args:
    #!/usr/bin/env bash
    if [[ "$1" == "{"* ]]; then {{qmp}} raw "$@"; else {{qmp}} hmp "$@"; fi
