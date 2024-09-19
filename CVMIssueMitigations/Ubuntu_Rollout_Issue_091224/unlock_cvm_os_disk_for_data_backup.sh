if [ $# -lt 1 ]; then
    echo "Usage: bash unlock_cvm_os_disk_for_data_backup.sh /path/to/recovery_key.bin"
    exit 1
fi

# Detect the LUKS encrypted partition
echo "Detecting LUKS encrypted partitions..."
luks_partition=$(lsblk -o NAME,FSTYPE | grep crypto_LUKS | awk '{print $1}' | sed 's/├─//g')

if [ -z "$luks_partition" ]; then
    echo "No LUKS encrypted partitions found."
    exit 1
fi

# Define the full path of the LUKS partition
luks_partition="/dev/$luks_partition"

# Unlock the LUKS partition
echo "Unlocking the partition $luks_partition..."
sudo cryptsetup luksOpen $luks_partition decrypted_cvm_partition < $1

if [ $? -ne 0 ]; then
    echo "Failed to unlock the partition. Check your recovery key."
    exit 1
fi

# Create mount point
mount_point="/mnt/cvm_fs/"
sudo mkdir -p $mount_point

# Mount the decrypted partition
echo "Mounting the decrypted partition..."
sudo mount /dev/mapper/decrypted_cvm_partition $mount_point

if [ $? -eq 0 ]; then
    echo "Partition mounted successfully at $mount_point."
    echo "You can access your files there."
else
    echo "Failed to mount the partition."
    sudo cryptsetup luksClose decrypted_cvm_partition
    exit 1
fi

echo
echo "To cleanup when finished, run:"
echo "sudo umount $mount_point"
echo "sudo cryptsetup luksClose decrypted_cvm_partition"