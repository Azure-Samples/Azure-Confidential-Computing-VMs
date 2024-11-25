# Attention Azure Confidential VM/Confidential GPU Users:

### Advisory - Virtual Machines
Potential downtime and reboots related to nullboot package (version 0.4.0-0ubuntu0.22.04.3) update
TNQ5-1X8.

### Impact Statement: 
Starting at 13:05 UTC on 19 November 2024, you have been identified as a customer using Virtual Machines, who may experience downtime during the new Ubuntu update and subsequent reboot. The impact of this issue is limited to a specific nullboot package (version 0.4.0-0ubuntu0.22.04.3) published by a third-party partner. This package contained an issue affecting "Confidential Virtual Machines" and "Confidential GPU Virtual Machines" using the DiskWithVMGuestState encryption type.

Customers who used this specific package version and subsequently booted their CVMs would have been prompted to enter a recovery key to unlock the machine. The problematic package has now been revoked by Canonical, and a newer version has been republished. As a result, for any future upgrades, the issue should already be mitigated.


### Recommended Action: 
We have identified a potential issue that may impact CVM and confidential GPU VM deployment. 
We advise customers against executing this upgrade path (nullboot package (version 0.4.0-0ubuntu0.22.04.3)). 
If you have already performed this upgrade and are experiencing downtime, please follow the below instruction for unblock and create a Microsoft support ticket at aka.ms/AzSupt with tracking ID TNQ5-1X8.


### Get the recovery key

To obtain a recovery key and unblock the VM boot, please follow the steps outlined below. Additional instructions on how to recover from the incorrectly installed nullboot package are currently under investigation and will be provided once available. (Please note: at this time, any updates or reinstallation of the existing nullboot package will fail.)

<strong>VM Guest State Only</strong> CVMs may skip this section since no recovery key is required to boot.

For <strong>Platform Managed Keys (PMK)</strong> and <strong>Customer Managed Keys (CMK)</strong>, please refer to the separate guidance provided later in this document, which is specific to your encryption type.

Generate a SAS URI for the VMGS file which is used to get the recovery key.

```
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