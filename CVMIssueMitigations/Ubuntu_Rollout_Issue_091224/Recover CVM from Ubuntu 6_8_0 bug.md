# Attention Azure Confidential VM Users:

It has come to the attention of the Azure Core Engineering team that the recent Linux kernel update from Canonical (version 6.8.0-1014-azure, released on September 12, 2024, at 20:00 UTC) may cause kernel panics and prevent Azure confidential VMs from booting. Although Canonical has withdrawn this kernel update as of September 17, 2024, at 04:04 UTC, your Azure confidential VM might still be affected.

If the CVM has been rebooted post the 6.8.0-1014-azure patch installation & now it is unresponsive due to kernel panic, the following kernel panic error message will be shown in serial console post reboot: 

**Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0) **

In this article, we will guide you through the steps to resolve this issue.

# How to identify the issue?
You can use below commend to identify whether VM kernel version has been updated to version 6.8. 

**Note**: This will work if the Confidential VM has not been re-booted after the installation of the kernel update.

```
apt list --installed | grep linux-image-6.8.0-1014-azure
```

# Prerequisites
Here are the pre-requisites you will need to install before going to the next steps.

- Requires PowerShell 7 (or pwsh), see https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell
- Requires AzCli, see https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
    - Run `az login` and `az account set --subscription <sub_id>` after installing
- Requires AzPowerShell for <strong>Customer Managed Key</strong> CVM recovery, see https://docs.microsoft.com/en-us/powershell/azure/install-az-ps
- Requires jq, available in major package managers
  - On PowerShell: `winget install jqlang.jq`
  - On Debian/Ubuntu: `sudo apt install jq`
  - Consult https://jqlang.github.io/jq/download/ for other platforms

If installing any packages, please start a new terminal session afterwards.

# Remediation of the Kernel Panic error

## Variables
Set variables for the affected CVM.
```
$vm_name="<name of the vm>"
$rg_name="<name of the resource group>"
$location="<name of the region>"
```
### Security Type
Set `$security_type` as follows:
- `ConfidentialVM_DiskEncryptedWithPlatformKey` if using Confidential Disk Encryption (CDE) with a Platform Managed Key (PMK)
- `ConfidentialVM_DiskEncryptedWithCustomerKey` if using CDE with a Customer Managed Key (CMK)
- `ConfidentialVM_VMGuestStateOnlyEncryptedWithPlatformKey` if not using CDE
```
$security_type="..."
```

### Set Recovery VM Variables
The recovery process will deploy a recovery VM to the same resource group as the affected CVM(s). A new temp OS disk is also required to detach the CVM's OS disk.
```
$recovery_vm_name="<name for new vm>"
$blank_disk_name="<name for temp disk>"
```
### Disk Encryption Set
If using CMK, provide a Disk Encryption Set ID to use when creating a blank OS disk
```
$des_id="/subscriptions/<sub_id>/resourceGroups/<rg_name>/providers/Microsoft.Compute/diskEncryptionSets/<des_name>"
```

## Create Recovery VM
The recovery VM is used to mount to CVM's OS disk and remove the 6.8.0 kernel from the EFI partition. It can be any VM and does not need to be a CVM itself. You can use the same recovery VM for multiple CVM recoveries if the affected resources are in the same resource group.

**Note**: We tested this process on a D-Series TVM.

### Deploy recovery resources

Create the recovery VM.

> You may need to change the VM Size depending on region and quota availability.
```
$vm_password="<set password>"
$recovery_vm=$(az vm create -g $rg_name -n $recovery_vm_name --image Canonical:ubuntu-24_04-lts:server:latest --size Standard_D2s_v4 --admin-username azureuser --admin-password $vm_password --location $location --security-type TrustedLaunch)
$recovery_vm_ip = $recovery_vm | jq -r ".publicIpaddress"
```

### Create Blank Disk

Create a blank disk to swap with the existing OS disk. This allows us to attach it to the recovery VM later.

Now, run the block associated with your CVM's security type.

#### PMK/VMGSOnly
```
$blank_disk=$(az disk create -g $rg_name --size-gb 30 --location $location --name $blank_disk_name --security-type $security_type --hyper-v-generation V2 --image-reference Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:latest)
```

#### CMK
```
$blank_disk=$(az disk create -g $rg_name --size-gb 30 --location $location --name $blank_disk_name --security-type $security_type --hyper-v-generation V2 --image-reference Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:latest --secure-vm-disk-encryption-set $des_id)
```

### Get the new disk's ID
```
$blank_disk_id = echo $blank_disk | jq -r ".id"
$os_disk_id = $(az vm show -g $rg_name -n $vm_name --query "storageProfile.osDisk.managedDisk.id")
$os_disk_name = $(az vm show -g $rg_name -n $vm_name --query "storageProfile.osDisk.name")
```

### Repair the Disk
Swap the OS disk out for the new blank disk

#### Deallocate the Disk
```
az vm deallocate -g $rg_name -n $vm_name
az vm update -g $rg_name -n $vm_name --os-disk $blank_disk_id
```

> Wait for the recovery VM to boot fully before attaching the disk, otherwise auto-mounting may prevent boot

#### Attach the Disk
```
az vm disk attach -g $rg_name --vm-name $recovery_vm_name --disks $os_disk_id
```

#### Inside the Recovery VM

Connect to the recovery VM
```
ssh azureuser@$recovery_vm_ip
```

<blockquote>
In the recovery VM, find the EFI partition in the CVM disk

```
lsblk -f | grep vfat | awk '$7 == "" {print $1}'
```

If there's no output, you can also determine the partition manually:

```
$ lsblk -f | grep vfat
├─sda15 vfat        FAT32 UEFI                9BD8-CDB5                              98.2M     6% /boot/efi
└─sdb15 vfat        FAT32 UEFI                1FEC-7DE7
```
The unmounted partition is `sdb15` since `sda15` is mounted to `/boot/efi` on the right.

Remove the unwanted kernel, replacing `sdb15` with the correct partition from above

```
sudo mkdir /cvm
sudo mount /dev/sdb15 /cvm
sudo rm /cvm/EFI/ubuntu/kernel.efi-6.8.0-1014-azure
```

Disconnect from the recovery VM.
</blockquote>

#### Detach the Disk
Detach the disk from the recovery VM and reattach it to the CVM

```
az vm disk detach -g $rg_name --vm-name $recovery_vm_name --name $os_disk_name
az vm update -g $rg_name -n $vm_name --os-disk $os_disk_id
```

### Get the recovery key
<strong>VMGSOnly</strong> CVMs may skip this section since no recovery key is required to boot.

For <strong>PMK</strong> and <strong>CMK</strong>, there is separate guidance later depending on your encryption type.

Generate a SAS URI for the VMGS file which is used to get the recovery key.

```
$disk_sas = $(az disk grant-access --access-level Read --duration-in-seconds 3600 --name $os_disk_name --resource-group $rg_name --secure-vm-guest-state-sas)
$vmgs_sas_uri = echo $disk_sas | jq -r ".securityDataAccessSas"
```

#### PMK
```
$response = Invoke-WebRequest -Uri $vmgs_sas_uri -Method Head
$headers = $response.Headers 
$headers | Export-Clixml "$location-headers.xml"
```

Provide Microsoft support with the VMGS headers to receive your recovery key.

#### CMK
The user running this script needs to have either
- RBAC Key Vault Crypto User on the CVM DES Key Vault <strong>if RBAC is enabled</strong>
- Unwrap Key permissions under the Key Vault Access Policy <strong>if RBAC is disabled</strong>

Update `$vmgsSas` with the contents of `$vmgs_sas_uri` at the top of `get_uki_recovery_key_cmk.ps1`
then execute the script in PowerShell, e.g.

> You may need to login with AzPowershell before running these commands: `Connect-AzAccount -Subscription <sub_id>`

```
./get_uki_recovery_key_cmk.ps1 -vmgs_sas_uri $vmgs_sas_uri
```

or

```
pwsh /path/to/get_uki_recovery_key_cmk.ps1 -vmgs_sas_uri $vmgs_sas_uri
```

Save the recovery key, e.g. `12345-67890-12345-67890-12345-67890-12345-67890`

### Boot the CVM

Cancel disk export after receiving the key so the VM can boot

```
az disk revoke-access --disk-name $os_disk_name --resource-group $rg_name
```

We can now reboot the VM to finish recovering the CVM
```
az vm start -g $rg_name -n $vm_name
```

For <strong>PMK</strong> or <strong>CMK</strong>, navigate to the CVM serial console in the Azure Portal and provide the recovery key when prompted during the boot process
> You can only copy-paste with the right-click menu

### Recover the CVM
The CVM now tries to boot into the non-existent kernel, so we need to modify the boot entries.

#### Check Boot Order

Connect to the recovery VM, or alternatively continue in the serial console
```
ssh azureuser@$recovery_vm_ip
```
<blockquote>
We can examine the entries with the following

```
$ efibootmgr
BootCurrent: 0003
Timeout: 0 seconds
BootOrder: 0002,0003
Boot0000* MsTemp
Boot0002* Ubuntu with kernel 6.8.0-1014-azure
Boot0003* Ubuntu with kernel 6.5.0-1025-azure
```

Please take a note of the entry for the good and bad kernel:

```
Bad (6.8.0-1014): Boot0002
Good:             Boot0003
```

#### Delete Boot Entry
In this example, the kernel we want to remove is `Boot0002`. It's denoted by `0002`. Delete the bad kernel entry, replacing `0002` as required

```
sudo efibootmgr -b 0002 --delete-bootnum
```

#### Set Boot Order
Set the boot order to your desired kernel

```
sudo efibootmgr --bootorder 0003
```

Reboot the VM
```
sudo reboot
```
No recovery key should be required anymore when rebooting, so you can connect through normal means, e.g. via SSH.

#### After Reboot
After rebooting and reconnecting to the VM, we can clean up the the 6.8.0 kernel package remnants

```
sudo apt update
sudo apt purge linux-image-6.8.0-1014-azure-fde linux-modules-6.8.0-1014-azure -y
sudo apt autoremove -y
sudo apt install linux-azure-fde -y
```
</blockquote>

# INTERNAL ONLY (TO BE REMOVED): To reproduce the boot failure
```
apt update; apt install linux-image-6.8.0-1014-azure-fde linux-modules-6.8.0-1014-azure
```
Note the new UKI
```
root@<REDACTED>uki-validation-pmk:/home/azureuser# ls /boot/efi/EFI/ubuntu/
BOOTX64.CSV  fbx64.efi  kernel.efi-6.5.0-1025-azure  kernel.efi-6.8.0-1014-azure  mmx64.efi  shimx64.efi
```
