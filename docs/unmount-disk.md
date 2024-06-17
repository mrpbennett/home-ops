# How to mount a disk in Ubuntu Server

Mounting a hard drive in Ubuntu Server involves several steps, including identifying the drive, creating a mount point, and updating the filesystem table to ensure the drive mounts automatically at boot. Here’s a step-by-step guide:

## Step 1: Identify the Hard Drive

1. **List all drives**: Run the following command to list all connected drives:

```
sudo fdisk -l
```

or

```bash
lsblk
```

This will show a list of all block devices. Identify your new hard drive (e.g., `/dev/sdb`).

## Step 2: Create a Partition (Optional)

If your hard drive is new and unpartitioned, you'll need to create a partition on it:

Run `fdisk`:

```bash
sudo fdisk /dev/sdb
```

Replace `/dev/sdb` with the correct drive identifier.

Inside `fdisk`:

- Press `n` to create a new partition.
- Follow the prompts to create a primary partition.
- Press `w` to write the changes and exit.

## Step 3: Format the Partition

Format the partition with the desired filesystem, for example, `ext4`:

```bash
sudo mkfs.ext4 /dev/sdb1
```

Replace `/dev/sdb1` with the correct partition identifier.

## Step 4: Create a Mount Point

Choose or create a directory where you want to mount the hard drive. For example, to create a mount point in `/mnt/storage`:

```bash
sudo mkdir -p /mnt/storage
```

## Step 5: Mount the Hard Drive

Mount the drive to the created mount point:

```bash
sudo mount /dev/sdb1 /mnt/storage
```

Replace `/dev/sdb1` and `/mnt/storage` with your actual partition and mount point.

## Step 6: Update fstab for Automatic Mounting

To ensure the drive mounts automatically on boot, you need to update the `/etc/fstab` file:

1. Open `/etc/fstab` in a text editor:

```bash
sudo nano /etc/fstab
```

2. Add a new entry:
   Add the following line to the end of the file:

```bash
/dev/sdb1  /mnt/storage  ext4  defaults  0  2
```

3. Save and Exit.

## Step 7: Verify the Mount

You can verify the mount by unmounting and remounting using `fstab`:

1. Unmount the drive

```bash
sudo umount /mnt/storage

sudo systemctl daemon-reload
```

2. Mount all filesystems in `fstab`:

```bash
sudo mount -a
```

3. Check the mount:

```
df -h
```

This should display your newly mounted hard drive under `/mnt/storage`.

## Summary

These steps outline the process of identifying, partitioning, formatting, creating a mount point, mounting, and configuring the hard drive to mount automatically on an Ubuntu Server. Adjust the commands to fit your specific drive identifiers and desired mount points.
