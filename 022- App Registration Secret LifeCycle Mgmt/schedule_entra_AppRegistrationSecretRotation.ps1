#------------------------------------
# Authentication
#------------------------------------
# authN to Azure with an account that has the ability to read & modify secrets in key vaults
try {
    if (-not (Get-AzContext)) { # check if there is already an account signed in, If Not... 
        connect-azaccount -identity | out-null # Connect as the resource itself
        write-output "Connected as the Managed Identity of the Automation Account."
    } # Otherwise use the signed in account
    else {
        Write-Output "Using existing Azure Connection: $((Get-AzContext).Account.Id)"
    }
}
catch {
    write-error "Failed to authenticate: $($_.Exception.Message)"
    throw
}

# authN as App Registration for Graph that has the ability to generate new secrets for any other app registration.
$clientID = "<00000-000000-000000-00000>" 
$clientSecret = Get-AzKeyVaultSecret -VaultName "<VaultName>" -Name "<secretName>" -AsPlainText
$tenantID = Get-AzKeyVaultSecret -VaultName "<VaultName>" -Name "<secretName>" -AsPlainText 
$resourceURL = "https://graph.microsoft.com/.default"
$body = @{
    client_id     = $clientId
    scope         = $resourceURL
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$token = (Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token" -Body $body).access_token  | ConvertTo-SecureString -AsPlainText -Force
Connect-MgGraph -AccessToken $token


#------------------------------------
# Initalize Variables
#------------------------------------
# EDIT THIS TO SET HOW OFTEN TO ROTATE SECRET
$secretRotateInDays = 30 # rotate any secret that is X days from "CREATION" (ie setting 30 equals every 30 days the secret renews)

$createNewSecretDate = (get-date).addDays(-$secretRotateInDays) # any secret found to be older than this will have a new one generated
$deleteOldSecretDate = (get-date).addDays(-$secretRotateInDays + 1) # Hold old secret for one extra day as a grace period

#------------------------------------
# Get Table Data from Storage Account
#------------------------------------
# Collect Data for all App Registrations whose secrets need to be rotated
$storageAccountName = "<storageAccountName>"
$tableName = "<tableStorageName"
$rawToken = (get-azaccesstoken -ResourceUrl "https://storage.azure.com").token
$token = ($rawToken -is [securestring]) ? (ConvertFrom-SecureString -SecureString $rawToken -AsPlainText) : $rawToken

$headers = @{
    Authorization  = "Bearer $token"
    'Content-type' = 'application/json'
    Accept         = "application/json;odata=nometadata"
    "x-ms-version" = "2026-02-06"
}
$uri = "https://$($storageAccountName).table.core.windows.net/$($tableName)?`$filter=PartitionKey eq 'appSecretLifecycleMgmtTable'"
try {
    $appRegistrations = (Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop).value | Select-Object displayName, appId, keyVaultName
}
catch {
	$errorStatus = $_
    write-error "Fail: [$($errorStatus.Exception.statuscode.value__) $($errorStatus.Exception.statuscode)] $(($errorStatus.ErrorDetails.Message | convertFrom-Json).error.message)"
	throw
}

#----------
# Functions
#----------
function New-CorpoAppRegistrationSecret {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][pscustomobject] $AppDetails,          # Get-MgApplication result
        [Parameter(Mandatory)][pscustomobject] $AppRegistration      # row from your table (displayName, keyVaultName, etc.)
    )
    # Create Secret
    try {
        $newSecret = Add-MgApplicationPassword -ApplicationId $AppDetails.id -PasswordCredential @{
            DisplayName = "auto-rotate-$(Get-Date -Format 'yyyyMMdd')"
            EndDateTime = (Get-Date).AddDays(180)
        } -ErrorAction Stop
    }
    catch {
        write-error "Failed to create secret: $_"
        throw
    }
    try {
        $kvParams = @{
            VaultName   = $AppRegistration.keyVaultName
            Name        = $AppRegistration.displayName
            SecretValue = (ConvertTo-SecureString $newSecret.SecretText -AsPlainText -Force)
        }
        Set-AzKeyVaultSecret @kvParams | Out-Null
    }
    catch {
        write-error "Failed to update KeyVault: $_"
        throw
    }
    return "- Success: Created secret '$($newSecret.displayName)' & stored in KeyVault '$($AppRegistration.keyVaultName)'"    
}


#---------------
# Rotate Secrets
#---------------
foreach($appRegistration in $appRegistrations){
    write-output "$($appRegistration.displayName): "
    try {
        # Validate values in Table & Store data in variables for use
        if (!($appDetails = get-mgapplication -filter "appId eq '$($appRegistration.appId)'" -ErrorAction Stop)){
            write-error "Unable to Find an app using ID" -ErrorAction Stop
        }
        $keyVault = Search-AzGraph -Query "Resources
            | where type == 'microsoft.keyvault/vaults'
            | where name =~ '$($appRegistration.keyVaultName)'
            | project name, resourceGroup, subscriptionId, location, id
        "
        if(-not $keyVault){ write-error "Unable to find keyVault listed in Table" -ErrorAction Stop}
        if( (get-azcontext).Subscription.id -ne $keyVault.data.subscriptionId ){ 
            Set-AzContext -SubscriptionId $keyVault.data.subscriptionId -ErrorAction Stop | out-null
        }
        write-output "- Validated '$($appRegistration.displayName)', proceeding..."

        # Check Secrets and Update
        $secrets = @( $appDetails.PasswordCredentials | Sort-Object StartDateTime -Descending )
        if ($secrets.count -eq 0){
            New-CorpoAppRegistrationSecret -AppDetails $appDetails -AppRegistration $appRegistration
        }
        else{
            # Create new Secret if latest is older than value set in the variables
            if ($secrets[0].StartDateTime -le $createNewSecretDate){
                New-CorpoAppRegistrationSecret -AppDetails $appDetails -AppRegistration $appRegistration
            }
            if ($secrets.count -gt 1 -and $secrets[1].StartDateTime -le $deleteOldSecretDate){
                foreach($secret in $secrets[1..($secrets.count -1)]){
                    Remove-MgApplicationPassword -ApplicationId $appDetails.id -KeyId $secret.KeyId -ErrorAction Stop
                    write-output "- Deleted Secret: $($secret.DisplayName)"
                }
            }
        }
        Write-Output "- Completed."
    }
    catch {
       Write-Output "Skip: Unable to process $($appRegistration.displayName): $($_.Exception.Message)"
       continue
    }
}
