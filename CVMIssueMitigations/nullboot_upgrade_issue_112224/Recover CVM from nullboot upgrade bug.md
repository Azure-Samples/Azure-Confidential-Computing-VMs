

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