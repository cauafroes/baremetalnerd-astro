#!/data/data/com.termux/files/usr/bin/sh

# Keep Termux awake in the background
termux-wake-lock

# Open a root shell and run the chroot setup
su -c sh << 'EOF'

# Fix locked screen networking
#dumpsys deviceidle disable

# Add Magisk busybox path
export PATH="/data/adb/magisk:$PATH"

UBUNTUPATH="/data/local/tmp/chrootubuntu"

# Fix storage/setuid permissions on Android data block
busybox mount -o remount,dev,suid /data

# 1. FIX INTERNET: Sync Android DNS settings before locking the jail
if [ -f /data/data/com.termux/files/usr/etc/resolv.conf ]; then
    cp /data/data/com.termux/files/usr/etc/resolv.conf $UBUNTUPATH/etc/resolv.conf
else
    echo "nameserver 8.8.8.8" > $UBUNTUPATH/etc/resolv.conf
fi

# 2. VIRTUAL FILESYSTEMS: Bind host core nodes
busybox mount --bind /dev $UBUNTUPATH/dev
busybox mount --bind /sys $UBUNTUPATH/sys
busybox mount --bind /proc $UBUNTUPATH/proc

# 3. PTY FIX: Explicitly mount devpts with standard Linux configuration flags
busybox mount -t devpts -o gid=5,mode=620 devpts $UBUNTUPATH/dev/pts

# Shared Memory Node (Always enable this; required for SSH keys generation and dbus)
busybox mount -t tmpfs -o size=256M tmpfs $UBUNTUPATH/dev/shm

# Mount internal Android sdcard storage
busybox mount --bind /sdcard $UBUNTUPATH/sdcard

# 4. FIX SERVICE BEHAVIOR: Run SSH server in foreground to maintain the jail
# This holds the script open so mounts stay active until you press Ctrl+C in Termux
echo "Starting OpenSSH Server in foreground... Press Ctrl+C in Termux to safely stop."
busybox chroot $UBUNTUPATH /usr/sbin/sshd -D

# 5. AUTOMATED CLEANUP: Safely teardown mounts only after SSH terminates
echo "SSH Server stopped. Cleaning up chroot mount points safely..."
busybox umount -l $UBUNTUPATH/sdcard
busybox umount -l $UBUNTUPATH/dev/shm
busybox umount -l $UBUNTUPATH/dev/pts
busybox umount -l $UBUNTUPATH/dev
busybox umount -l $UBUNTUPATH/proc
busybox umount -l $UBUNTUPATH/sys

EOF

# Release wakelock when fully closed
termux-wake-unlock
