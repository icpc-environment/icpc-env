# SER ICPC Contest Image Tools

This repository contains the tools necessary to build the ACM ICPC Southeast Regional contestant image. The contestant image is a linux installation optimized for booting off a flash drive that is used by all the teams in our region.

## Key Features
This image has been tuned and tweaked over the years, but it currently supports the following:

* A wide array of programming languages: c, c++, java, haskell, pascal, python2/3, scala, fortran, ADA, c#, f#, D, lua, go, ruby, erlang, groovy, nim, clojure, prolog, objective-c
* Multiple IDEs and developer tools: Eclipse(with PyDev/CDT), Monodevelop, Code::Blocks, gvim, emacs, atom, gedit, Visual Studio Code, Geany, IntelliJ
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
* USB boot capable
* 1gb of ram(2+ recommended)
* 16gb flash drive(USB3.0 preferred)

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
git clone https://github.com/icpc-environment/icpc-env.git
cd icpc-env
```

2. Make sure dependencies are met
  * Install required packages

    ```bash
    sudo apt-get install qemu-system-x86 genisoimage bsdtar ansible
    ```
  * Generate an ssh keypair(without a password) that will be used during building the image

    ```bash
    ssh-keygen -f configs/ssh_key -t rsa -C "ICPC Environment Key" -N ""
    ```

    Then edit the file config/1804_ks.cfg and insert the public key portion in the appropriate location

  * Download the 64 bit version of Ubuntu 14.04 Server:

    ```bash
    wget http://releases.ubuntu.com/14.04/ubuntu-14.04.3-server-amd64.iso # 64 bit
    wget http://releases.ubuntu.com/14.04/ubuntu-14.04.3-server-i386.iso  # 32 bit
    ```
  * Download the 64 bit version of eclipse mars into the `files/` directory:  
    http://www.eclipse.org/downloads/packages/release/mars/r

    ```bash
    wget -O files/eclipse64.tar.gz  http://url/to/64bit/version  # 64bit
    ```

3. Run the `create_baseimg.sh` script to create an unattended installation disk for ubuntu,
perform the installation, and leave the base image ready for processing. During this
step you can specify how large you want the image to be(Default 7200M to fit on most
8GB flash drives)
```bash
./create_baseimg.sh # optionally add '-s 14200M'
```

Set up an NFS Server(for quicker rebuilds).
```bash
sudo apt install nfs-kernel-server
cat /srv/icpc_cache 127.0.0.1(rw,sync,no_subtree_check,no_root_squash,insecure) | sudo tee -a /etc/exports
sudo exportfs -av
```

4. Build the actual contestant image. This step takes the base image, boots it up,
runs ansible to configure everything, performs a few final cleanup steps, and finally
powers it off. Take a walk, this step takes some time(10-30minutes)
```bash
./build-final.sh
```

5. Take the newly minted image and copy it to a usb drive(as root)
```
# WARNING: Make sure to replace /dev/sdx with your actual device
sudo dd if=output/2015-10-22_image-amd64.img of=/dev/sdx bs=1M
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
`configs/1404_install.seed` file. By default you'll get a 192MB Fat32 partition
and the rest of the space will be dedicated to the image itself. 14200M works well
as a default size and fits easily on most 16G flash drives you'll encounter.

### Testing customizations
There is a script available to help with development so you don't have to build
the full image, wait for it to copy to a usb drive, and then boot.

Follow steps 1,2,3 above, but instead of running the `build-final.sh` script,
instead run `./runvm.sh`. This will start a VM off the base image, run ansible,
and then give you the opportunity to re-run ansible, start an ssh session, or
terminate the vm.

Once you have ansible performing all the tasks you need, halt the vm, then
continue with step 4 above. You should never use an image created by the
`runvm.sh` script, always build images using `build-final.sh`

## Tips for building
Running your own local apt mirror will greatly speed up the process(at the
expense of disk space)
See `files/sources-local-mirror.list` for the default mirror setup.
