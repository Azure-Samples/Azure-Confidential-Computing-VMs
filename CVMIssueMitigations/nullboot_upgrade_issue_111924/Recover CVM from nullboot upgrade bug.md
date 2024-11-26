# Attention Azure Confidential VM/Confidential GPU VM Users:

### Advisory - Virtual Machines
Potential downtime and reboots related to nullboot package (version 0.4.0-0ubuntu0.22.04.3) update
TNQ5-1X8.

### Impact Statement: 
Starting at 13:05 UTC on 19 November 2024, you have been identified as a customer using Virtual Machines, who may experience downtime during the new Ubuntu update and subsequent reboot. The impact of this issue is limited to a specific nullboot package (version 0.4.0-0ubuntu0.22.04.3) published by Canonical. This package contained an issue affecting "Confidential Virtual Machines" and "Confidential GPU Virtual Machines" using the DiskWithVMGuestState encryption type.

Customers who used this specific package version and subsequently booted their CVMs would have been prompted to enter a recovery key to unlock the machine. The problematic package has now been revoked by Canonical, and a newer version has been republished. As a result, for any future upgrades, the issue should already be mitigated.


### Recommended Action: 
We have identified a potential issue that may impact CVM and confidential GPU VM deployment. 
We advise customers against executing this upgrade path (nullboot package (version 0.4.0-0ubuntu0.22.04.3)). 
- Check wether your VM is impacted:
    ```
    apt list --installed nullboot

    # If the installed version is NOT 0.4.0-0ubuntu0.22.04.3, you are not impacted.
    # If the installed version is 0.4.0-0ubuntu0.22.04.3, do NOT reboot, immediately run
    sudo apt update
    sudo apt install nullboot
    ```

- If you have already performed this upgrade and are experiencing downtime, please follow the below instruction for unblock and create a Microsoft support ticket at aka.ms/AzSupt with tracking ID TNQ5-1X8.


### Get the recovery key

To obtain a recovery key and unblock the VM boot, please follow the steps outlined below. Additional instructions on how to recover from the incorrectly installed nullboot package are currently under investigation and will be provided once available. (Please note: at this time, any updates or reinstallation of the existing nullboot package will fail.)

#### Prerequisites
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

For affected CVMs that are encrypted using a Customer Managed Key, make sure the user running these commands has either
- RBAC Key Vault Crypto User on the CVM DES Key Vault <strong>if RBAC is enabled</strong>
- Unwrap Key permissions under the Key Vault Access Policy <strong>if RBAC is disabled</strong>

#### Get Disk vmgs info for recovery keys
<strong>VM Guest State Only</strong> CVMs may skip this section since no recovery key is required to boot.

For <strong>Platform Managed Keys (PMK)</strong> and <strong>Customer Managed Keys (CMK)</strong>, please refer to the separate guidance provided later in this document, which is specific to your encryption type.

Generate a SAS URI for the VMGS file which is used to get the recovery key.

```
$vm_name="<name of the vm>"
$rg_name="<name of the resource group>"
$location="<name of the region>"
$os_disk_id = $(az vm show -g $rg_name -n $vm_name --query "storageProfile.osDisk.managedDisk.id")
$os_disk_name = $(az vm show -g $rg_name -n $vm_name --query "storageProfile.osDisk.name")

# please stop the VM and run 
$disk_sas = $(az disk grant-access --access-level Read --duration-in-seconds 3600 --name $os_disk_name --resource-group $rg_name --secure-vm-guest-state-sas)
$vmgs_sas_uri = echo $disk_sas | jq -r ".securityDataAccessSas"
```

#### PMK
For PMK customer, please create Microsoft support ticket at aka.ms/AzSupt with tracking ID TNQ5-1X8.
```
$response = Invoke-WebRequest -Uri $vmgs_sas_uri -Method Head
$headers = $response.Headers 
$headers | Export-Clixml "$location-headers.xml"
```

Provide Microsoft support with the VMGS headers to receive your recovery key.

#### CMK

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

```
# After getting the recovery key, need to release the disk access before starting the VM.  
az disk revoke-access --disk-name $os_disk_name --resource-group $rg_name
```