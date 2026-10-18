---
title: "Turn an old android into a Native Linux Server with chroot"
date: 2026-09-27T10:00:00Z
layout: ../../../layouts/Layout.astro
draft: false
tags: ["linux", "android", "chroot", "hardware", "embedded", "raspberry-pi"]
categories: ["Bare Metal"]
description: "Why buy a Raspberry Pi when your old smartphone has faster UFS storage, an integrated UPS battery, and an octa-core ARM processor? Here is how and why chrooting Linux creates a really cool home server."
---

If you have an old flagship smartphone sitting in a drawer gathering dust, you are holding a performant, power-efficient micro-server. While single-board computers (SBCs) like the Raspberry Pi remain the default choice for self-hosters and home lab enthusiasts, old smartphones often outperform them in raw specs, built-in redundancy, and overall value.

By leveraging **`chroot`** (change root) on a rooted Android device, you can bypass the performance or software limitations of user-space terminal emulators like Termux + PRoot and run a native ARM64 Linux environment alongside the Linux kernel.

For this project we will be using an aging **Galaxy S8**, but you can use pretty much any phone.

> [NOTE]
> A lot of the technical material about chrooting via termux in this post is sourced from **[Ivon Blog](https://ivonblog.com)**. Check out their site for more projects.

---

## Hardware Breakdown: Galaxy S8 vs. Raspberry Pi 4

When comparing single-board computers to decommissioned flagship hardware, the specs of the smartphone speak for themselves:

| Hardware Component | Samsung Galaxy S8 (Exynos 8895 / SD 835) | Raspberry Pi 4 (4GB Model) |
| :--- | :--- | :--- |
| **CPU Architecture** | Octa-Core (4x2.3 GHz + 4x1.7 GHz) | Quad-Core Cortex-A72 @ 1.5 GHz |
| **Storage Speed** | 64GB **UFS 2.1** (~500 MB/s read) | MicroSD Card (~30–90 MB/s read) |
| **Built-in Power Backup** | 3,000 mAh Li-Ion (Integrated UPS) | None (Requires external UPS) |
| **Network & Wireless** | Wi-Fi 5 (802.11ac), Bluetooth 5.0, LTE | Wi-Fi 5 (802.11ac), Bluetooth 5.0, Gigabit Ethernet |
| **Display / Touch** | Integrated 1440p Super AMOLED Display | Requires external HDMI monitor |
| **Cost** | **$0** (Reused hardware) | ~$55–$75+ (Board only, no power/storage) |

---

## Where a Chrooted Smartphone Wins

### 1. Superior Performance (Faster CPU, Ram and storage)
The primary bottleneck on most Raspberry Pi setups is the MicroSD card. MicroSD cards offer poor random write performance and frequently fail under database-heavy workloads (e.g., SQLite, Docker containers, logging daemons). 

The Galaxy S8 utilizes onboard **UFS 2.1 flash memory**, delivering read/write performance comparable to an entry-level/slow SATA SSD:

```text
# MicroSD Sequential Write Speed (Raspberry Pi)
~25 MB/s to 45 MB/s

# Galaxy S8 UFS 2.1 Sequential Write Speed
~180 MB/s to 220 MB/s
```

Not only that, but old flagships still **outperform most cheap SBCs in ram and cpu**.

### 2. Built-In Battery Backup (Uninterruptible Power Supply)
A momentary power flicker can corrupt a Raspberry Pi’s filesystem if it is writing to disk. A smartphone comes with a built-in battery that acts as an integrated UPS. If your mains power drops, your home server continues running, keeping network sockets, background daemons, and cron jobs active without interruption.

### 3. Integrated Diagnostics & Status Display
When a headless server drops off the local network, debugging a Raspberry Pi requires an HDMI adapter and a external monitor. An old phone provides an integrated, high-density touch display right out of the box—ideal for rendering system statistics via htop or showing custom server dashboards.

---

## Where regular SBCs win

### 1. Ease Of Use
It's really easy to start using a Raspberry pi: most of the times it just works. There is lots of tutorials. The distro broke? Flash the SD card again. The phone setup isn't going to be as easy, but will make you learn more about termux, scripting, chrooting, etc.

### 2. I/O
Most main SBCs have ethernet, Wi-Fi, Bluetooth, USB and GPIO built-in the board. The phone is a bit more limited, we can use its USB-OTG to connect other devices such as microcontrollers to have GPIO, usb-ethernet adapters and use regular wifi and bluetooth via android, but isn't as easy as the SBC.

---

## What Is `chroot` and Why Not Use PRoot?

Most Android Linux tutorials rely on **PRoot** (via Termux), which uses `ptrace` in user space to simulate root access and intercept system calls without unlocking the bootloader. 

While PRoot is easy to set up and doesn't need a rooted phone, system call interception incurs significant CPU overhead:

```text
User Application ---> [ ptrace overhead ] ---> PRoot Layer ---> Android Kernel
```

With **`chroot`**, you execute commands directly against the underlying Android Linux kernel with full root privileges:

```text
User Application ---> Native System Calls ---> Android Linux Kernel
```

Because `chroot` uses native system calls without virtualization or call-trapping layers, your Ubuntu environment runs at **100% native hardware speeds**.

---

## Setting Up Ubuntu via `chroot` on Android

### Prerequisites
* A rooted ARM64/aarch64 Android device with root access.
* `Termux` installed via F-droid website.
* BusyBox installed on the phone (we will be using the **included busybox from Magisk**).
* An Ubuntu ARM64 rootfs image (e.g., `ubuntu-base-24.04.2-base-arm64.tar.gz`).
* **Optional:** SSHD setup in termux so you can run all these commands from your pc.

### Start
For this example i will be using a galaxy S8 on Lineage OS 19 on Linux kernel 4.4.302 - This procedure may differ if you're using other android versions or kernels. Google an AI are great allies in case you have any problems.

### Step 1: Create the Chroot Directory Structure
In termux, enter shell as root and create our chroot folder and some mountpoints:

```bash
su
mkdir -p /data/local/ubuntu
cd /data/local/ubuntu
mkdir sdcard
mkdir dev/shm
```

### Step 2: Extract the Root Filesystem
Transfer and extract the official Ubuntu ARM64 base image into your chroot target:

```bash
cd /data/local/ubuntu
busybox wget https://cdimage.ubuntu.com/ubuntu-base/releases/noble/release/ubuntu-base-24.04.2-base-arm64.tar.gz
tar xpvf ubuntu-base-*-base-arm64.tar.gz --numeric-owner
```

> **Note:** If you see the error `/system/bin/sh: busybox: inaccessible or not found`, Magisk's BusyBox is likely not in your `PATH`. 
> 
> To fix this, add it to your `PATH` by running:
> ```bash
> export PATH="/data/adb/magisk:$PATH"
> ```

### Step 3: Creating a script to enter and test chroot
You may run everything manually in your shell to enter chroot, but, would be a tedious and long process every time, so we created a script to do it for us. To give the chroot environment access to system hardware, process tables, and network interfaces, mount `dev`, `proc`, and `sys`:

```bash
cd ../ #we will be in /data/local
vi startu.sh
```

**Paste this:**
```bash
#!/bin/sh

# If you didn't have the busybox path problem you can remove this line below
export PATH="/data/adb/magisk:$PATH"

# The path of Ubuntu rootfs
UBUNTUPATH="/data/local/ubuntu"

# Fix setuid issue
busybox mount -o remount,dev,suid /data

busybox mount --bind /dev $UBUNTUPATH/dev
busybox mount --bind /sys $UBUNTUPATH/sys
busybox mount --bind /proc $UBUNTUPATH/proc
busybox mount -t devpts devpts $UBUNTUPATH/dev/pts

busybox mount --bind /sdcard $UBUNTUPATH/sdcard
# chroot into Ubuntu
busybox chroot $UBUNTUPATH /bin/su - root

busybox umount $UBUNTUPATH/dev/shm
busybox umount $UBUNTUPATH/dev/pts
busybox umount $UBUNTUPATH/dev
busybox umount $UBUNTUPATH/proc
busybox umount $UBUNTUPATH/sys
busybox umount $UBUNTUPATH/sdcard

```

Make the script executable:
```bash
chmod +x startu.sh
```

### Step 4: Setup the Chroot Environment
Test the script you just created. If everything is right, you should drop on a `root@localhost` shell. We have a few settings to do:

Setup DNS
```bash
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "127.0.0.1 localhost" > /etc/hosts
```

Setup standard Linux users (_apt and root) with Android-specific GIDs (3003/3004) so package management and networking work properly inside an Android chroot or container
```bash
groupadd -g 3003 aid_inet
groupadd -g 3004 aid_net_raw
groupadd -g 1003 aid_graphics
usermod -g 3003 -G 3003,3004 -a _apt
usermod -G 3003 -a root
```

Try using apt
```bash
apt update
apt upgrade
apt install -y sudo htop openssh-server openssh-client neofetch curl git
```

---

## Best Use Cases for a Chrooted Smartphone Server

* **Self-Hosted Services:** Run lightweight servers like Pi-hole, AdGuard Home, or Syncthing.
* **Low-Power Web Server:** Host static sites (including Hugo!) using Nginx or Caddy.
* **MQTT & Home Automation:** Serve as an MQTT broker (`mosquitto`) or Node-RED automation node.
* **Network Storage / Backup:** Attach USB storage OTG docks to turn the phone into an ultra-portable NAS or rsync target.

---

## Conclusion

Before buying another single-board computer for your home lab, look into your drawer of old gadgets. With native `chroot` access, a recycled smartphone like the Galaxy S8 provides a faster, safer, and self-powered Linux node completely free of charge.