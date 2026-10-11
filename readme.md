# ICPC Contest Image Tools

This repository contains the tools necessary to build the ICPC Southeast Regional contestant image. The contestant image is a linux installation optimized for booting off a flash drive that is used by all the teams in our region.

## Key Features
This image has been tuned and tweaked over the years, but it currently supports the following:

* A wide array of programming languages: c, c++, java, kotlin, haskell, pascal, python3, scala, fortran, ADA, c#, f#, D, lua, go, ruby, erlang, groovy, nim, clojure, prolog, objective-c
* Multiple IDEs and developer tools: Eclipse(with PyDev/CDT), Code::Blocks, gvim, emacs, gedit, Visual Studio Code, Geany, IntelliJ(IDEA/CLion/PyCharm), CodeLite, neovim
* Local devdocs server for language documentation
* Automatically populate the linux disk cache on boot to speed up response time for certain programs
* Advanced firewall to restrict team access to the network
* Fat32 partition for teams to store files that allows for easy access after the contest
* Simple management/set up for admins
* Custom home directory content(for configuring firefox, desktop shortcuts, etc)
* Fully customizable, entirely automated process for building consistent images
* Lightweight XFCE window manager

## Usage Requirements
* 64bit hardware
* USB boot capable(BIOS + UEFI supported)
* 4gb of ram(8+ recommended)
* 32gb flash drive(USB3.0 strongly recommended)

## Build Requirements
* Linux host system
* Hardware Virtualization (KVM)
* Approx 30GB disk space free

## Building the Image
Building the image is a very simple process, and takes about 45 minutes
depending on connection speed and various other factors.

1. Clone this repository:
```bash
git clone https://github.com/icpc-environment/icpc-env.git icpcenv
cd icpcenv
```
1. Install mise (and make sure it's activated in your shell) - https://mise.jdx.dev/
1. Make sure dependencies are met
    ```bash
    sudo apt-get install qemu-system-x86 libarchive-tools xorriso parted ovmf jq

    # Configure/trust this for mise
    mise trust && mise install

    # Create the venv
    just dependencies
    ```
1. Edit `group_vars/generic.yml` to your liking. Specifically set the icpcadmin password, timezone, and reverseproxy_sites to configure the firewall.
1. Run `just baseimage` to create an unattended installation disk for ubuntu,
perform the installation, and leave the base image ready for processing. This step takes around 5-10 minutes depending on system and internet speed.
```bash
just baseimage
```
1. Build the actual contestant image. This step takes the base image, boots it up,
runs ansible to configure everything, performs a few final cleanup steps, and finally
powers it off. Take a walk, this step takes some time(~30 minutes)
```bash
./build-final.sh
```
1. Take the newly minted image and copy it to a usb drive (or hard drive) (as root)
```
# WARNING: Make sure to replace /dev/sdx with your actual device
sudo dd if=output/generic-2026-09-01_image-amd64.img of=/dev/sdx bs=1M status=progress oflag=direct conv=sparse
```

## Customization of the Image
One of our goals with this image is for it to be easily customized. To achieve this
the image is configured using Ansible. Ansible is kicked off with the `main.yml`
file, which mostly just includes things in the `playbooks/` subdirectory. Support files
for ansible are found in the `files/` subdirectory, and variables in `group_vars/`.

Some of the ansible plays depend on variables that you can set in the files in
the `group_vars/` directory (you'll primarily touch `generic.yml`, unless you're
configuring this for multiple contests). That's where you'll want to go to edit the
contest admin password and configure what urls contestants are allowed to access.

If you want to customize the partition layout, you'll need to edit the
`configs/2604_autoinstall.yaml` file. By default you'll get a 192MB Fat32 partition
and the rest of the space will be dedicated to the image itself. You can
also run `create_baseimg.sh` with `--no-usb` to skip getting the 192MB Fat32 partition
if you don't intend to use these on usb drives the contestants get to keep.

### Testing customizations
There is a script available to help with development so you don't have to build
the full image, wait for it to copy to a usb drive, and then boot.

Follow the steps above until you get to running the `build-final.sh` script;
but run `./runvm.sh` instead. This will start a VM off the base image, then
give you a menu allowing you to run ansible, ssh in, and a few other utility
functions. There are also some slightly more complex scripts for development in
the `dev/` directory, which has its own readme.

Once you have ansible performing all the tasks you need, halt the vm, then
continue with the `build-final.sh` script. You should never use an image created
by the `runvm.sh` script, always build images using `build-final.sh`.
