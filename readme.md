# ICPC Contest Image Tools

This repository contains the tools necessary to build the ICPC Southeast Regional contestant image. The contestant image is a linux installation optimized for booting off a flash drive that is used by all the teams in our region.

## Key Features
This image has been tuned and tweaked over the years, but it currently supports the following:

* A wide array of programming languages: c, c++, java, haskell, pascal, python2/3, scala, fortran, ADA, c#, f#, D, lua, go, ruby, erlang, groovy, nim, clojure, prolog, objective-c
* Multiple IDEs and developer tools: Eclipse(with PyDev/CDT), Monodevelop, Code::Blocks, gvim, emacs, gedit, Visual Studio Code, Geany, IntelliJ
* Local web server with copies of language documentation for: STL, Scala, Java, Python2/3, Pascal, Haskell
* Automatically populate the linux disk cache on boot to speed up response time for certain programs
* Automatic login of teams to DOMjudge without giving teams access to their credentials
* Advanced firewall to restrict team access to the network
* Fat32 partition for teams to store files that allows for easy access after the contest
* Supports 32 and 64 bit machines
* Simple management/set up for admins
* Custom home directory content(for configuring firefox, desktop shortcuts, etc)
* Fully customizable, entirely automated process for building consistent images
* Lightweight XFCE window manager

## Usage Requirements
* 64bit hardware
* USB boot capable(BIOS + UEFI supported)
* 1gb of ram(2+ recommended)
* 32gb flash drive(USB3.0 strongly recommended)

## Build Requirements
* Linux host system
* qemu, uml-utlities
* Approx 30GB disk space free
* Ansible

## Building the Image
Building the image is a very simple process, and takes between 10-30minutes
depending on connection speed and various other factors.

1. Clone this repository:
```bash
git clone http://github.com/icpc-env/icpc-environment.git icpcenv
cd icpcenv
```

1. Make sure dependencies are met
  * Install required packages

    ```bash
    sudo apt-get install qemu-system-x86 genisoimage bsdtar ansible
    ```
  * Download the 64 bit version of Ubuntu 20.04 Server:
    ```bash
    wget https://releases.ubuntu.com/20.04/ubuntu-20.04.5-live-server-amd64.iso
    ```
  * Download the 64 bit version of eclipse into the `files/` directory:
    ```bash
    cd files && wget https://ftp.osuosl.org/pub/eclipse/technology/epp/downloads/release/2022-09/R/eclipse-java-2022-09-R-linux-gtk-x86_64.tar.gz
    ```

1. Run `secrets/gen-secrets.sh` to create some ssh keys/other secret data. Follow this with `./fetch-secrets.sh` to put them in the right place for ansible.

1. Copy `group_vars/all.dist` to `group_vars/all` and edit it to your liking. Specifically
set the icpcadmin password, and firewall expiration properly.

1. Run the `create_baseimg.sh` script to create an unattended installation disk for ubuntu,
perform the installation, and leave the base image ready for processing. During this
step you can specify how large you want the image to be(Default 28500M to fit on most
32G flash drives).
```bash
# This step takes around 3-5minutes depending on system/internet speed.
./create_baseimg.sh # optionally add '-s 28500M', or --no-usb
```
1. Build the actual contestant image. This step takes the base image, boots it up,
runs ansible to configure everything, performs a few final cleanup steps, and finally
powers it off. Take a walk, this step takes some time(10-30minutes)
```bash
./build-final.sh
```

1. Take the newly minted image and copy it to a usb drive (or hard drive) (as root)
```
# WARNING: Make sure to replace /dev/sdx with your actual device
sudo dd if=output/2020-09-01_image-amd64.img of=/dev/sdx bs=1M status=progress oflag=direct conv=sparse
```

## Customization of the Image
One of our goals with this image is for it to be easily customized. To achieve this
the image is configured using Ansible. Ansible is kicked off with the `main.yml`
file, which mostly just includes things in the `playbooks/` subdirectory. For more
details please refer to `playbooks/readme.yml`. Support files for ansible are
found in the `files/` subdirectory.

Some of the ansible plays depend on variables that you can set in the file
`group_vars/all`. Please refer to `group_vars/all.dist` for an example of what
this file should contain. That's where you'll want to go to edit the contest
admin password and configure what urls contestants are allowed to access.

If you want to customize the partition layout, you'll need to edit the
`configs/2004_autoinnstall.yaml` file. By default you'll get a 192MB Fat32 partition
and the rest of the space will be dedicated to the image itself. 14700M works well
as a default size and fits easily on most 16G flash drives you'll encounter. You can
also run `create_baseimage.sh` with `--no-usb` to skip getting the 192MB Fat32 partition
if you don't intend to use these on usb drives the contestants get to keep.

### Testing customizations
There is a script available to help with development so you don't have to build
the full image, wait for it to copy to a usb drive, and then boot.

Follow steps the above until you get to running the `build-final.sh` script;
instead run `./runvm.sh` instead. This will start a VM off the base image, then
give you a menu allowing you to run ansible, ssh in, and a few other utility
functions.

Once you have ansible performing all the tasks you need, halt the vm, then
continue with the `build-final.sh` script. You should never use an image created
by the `runvm.sh` script, always build images using `build-final.sh`
