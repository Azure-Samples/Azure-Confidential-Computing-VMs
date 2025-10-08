Param (
    [Parameter(Mandatory=$true)]
    [string]$vmgs_sas_uri
)
# Replace VM Guest State VHD Url and run the script
$vmgsSas = $vmgs_sas_uri
$response = $null
$response = Invoke-WebRequest -Uri $vmgsSas -Method Head
if (-not $response) {
    throw "Get headers request for VMGS disk failse."
}
$headers = $response.Headers
if (-not $headers.ContainsKey('x-ms-meta-Cvm_recovery_key_alg')) {
    throw 'x-ms-meta-Cvm_recovery_key_alg does not exist'
}
if (-not $headers.ContainsKey('x-ms-meta-Cvm_recovery_key_identifier')) {
    throw 'x-ms-meta-Cvm_recovery_key_identifier does not exist'
}
if (-not $headers.ContainsKey('x-ms-meta-Cvm_wrapped_recovery_key')) {
    throw 'x-ms-meta-Cvm_wrapped_recovery_key does not exist'
}
if (-not $headers.ContainsKey('x-ms-meta-Cvm_recovery_key_os_type')) {
    throw 'x-ms-meta-Cvm_recovery_key_os_type does not exist'
}
$algorithm = $headers.'x-ms-meta-Cvm_recovery_key_alg'
$keyUri = $headers.'x-ms-meta-Cvm_recovery_key_identifier'
$wrappedKey = $headers.'x-ms-meta-Cvm_wrapped_recovery_key'
$osType = $headers.'x-ms-meta-Cvm_recovery_key_os_type'

$azureAccessToken = $null
if ($host.Version.Major -eq 5) {
    $resource = [uri]$keyUri
} else {
    $resource = [uri]$keyUri.GetValue(0)
}
if ($resource.Authority.EndsWith("vault.azure.net")) {
    $azureAccessToken = Get-AzAccessToken -ResourceUrl "https://vault.azure.net"
} else {
    $azureAccessToken = Get-AzAccessToken -ResourceUrl "https://managedhsm.azure.net"
}

# New AzCLI SDK versions has Token of type System.Security.SecureString
if ($azureAccessToken.Token -is [System.Security.SecureString])
{
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($azureAccessToken.Token)
    try
    {
        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally
    {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}
else
{
    $token = $azureAccessToken.Token
}

$headers = @{'Authorization' = "Bearer $($token)"; "Content-Type" = "application/json"}
$Body = @{
    "alg" = "$($algorithm)"
    "value" = "$($wrappedKey)"
}
$unwrapUri = $keyUri.TrimEnd("/") + "/unwrapkey?api-version=7.1"
$Parameters = @{
    Method = "POST"
    Uri = "$($unwrapUri)"
    Body = ($Body | ConvertTo-Json)
    Headers = $headers
}

$response = Invoke-RestMethod @Parameters #response in base64
If (-not $response) {
    throw "Can't recieve an answer from $unwrapUri"
} # Convert Base64Url string returned by KeyVault unwrap to Base64 string
$secretBase64 = $response.value
$secretBase64 = $secretBase64.Replace('-', '+');
$secretBase64 = $secretBase64.Replace('_', '/');
if ($secretBase64.Length %4 -eq 2) {
    $secretBase64+= '==';
} elseif ($secretBase64.Length %4 -eq 3) {
    $secretBase64+= '=';
}
if ($osType -eq "Windows") {
    $recoveryKey = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($secretBase64))
    Write-Host "Windows recovery key is : $recoveryKey"
} else {
    # Linux
    $byteArray = [Convert]::FromBase64String($secretBase64)
    if ($byteArray.Length -ne 16) {
        throw "Byte array size is not of correct length"
    }
    $recoveryArray = New-Object System.Collections.ArrayList
    for($i = 0; $i -le 7; $i++) {
        $recoveryArray.Add([bitconverter]::ToUInt16($byteArray,$i * 2).ToString("D5")) | Out-Null
    }
    $recoveryKey = $recoveryArray -join "-"
    Write-Host "Linux recovery key is : $recoveryKey"

    # Define the output file path
    $outputFile = "./cvm_recovery_key.bin"
    [Environment]::CurrentDirectory = $pwd
    Write-Host "Backing up recovery key bytearray to file $outputFile"

    # Write the byte array to a file
    [System.IO.File]::WriteAllBytes($outputFile, $byteArray)
}