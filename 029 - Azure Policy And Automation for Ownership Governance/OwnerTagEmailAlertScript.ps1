#-------------
# Authenticate
#-------------
# To Azure
try {
    if (-not (Get-AzContext)) {
        # check if there is already an account signed in, If Not... 
        connect-azaccount -identity | out-null # Connect as Self
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

#----------
# Variables
#----------
# Set the keys for the owner tags. I will make it programmatic so you dont have to use owner1 and owner2. ie corp-primary-owner/corp-secondary-owner
$owner1Key = "owner1" 
$owner2Key = "owner2"

$kvName = "<KVNAme>"
$tenantID = Get-AzKeyVaultSecret -VaultName $kvName -Name "tenantID" -AsPlainText


#-----------------------------------------
# Get All Resources & Resource Groups Tags
#-----------------------------------------
$excludeResourceTypes = @( 
    "microsoft.automation/automationaccounts/runbooks",
    "microsoft.insights/actiongroups",
    "microsoft.operationalinsights/querypacks",
    "microsoft.alertsmanagement/smartdetectoralertrules"
)
$excludeFilter = ($excludeResourceTypes | ForEach-Object { "'$_'" }) -join ","

$scopes = Search-AzGraph -first 1000 -Query @"
resourcecontainers
| where type == "microsoft.resources/subscriptions/resourcegroups"
| project 
    scope = "Resource Group", 
    name, 
    Tag_$owner1Key = tostring(tags["$owner1Key"]), 
    Tag_$owner2Key = tostring(tags["$owner2Key"]),
    ResourceId = id,
    type
// If you want to add search at the resource level you can do so here or remove "| union ( <data> )" if you want to omit
| union (
    resources
    | where type !in~ ($excludeFilter)
    | project 
        scope = strcat("Resource (", tostring(split(type, "/")[-1]), ")"),
        name, 
        Tag_$owner1Key = tostring(tags["$owner1Key"]), 
        Tag_$owner2Key = tostring(tags["$owner2Key"]),
        ResourceId = id,
        type
)
| order by scope asc
"@

#--------------------------
# Collect Data from EntraID
#--------------------------
$clientName = "<clientName>"
$clientID = "<clientID>"
$clientSecret = Get-AzKeyVaultSecret -VaultName $kvName -Name $clientName -AsPlainText
$connection = New-CorpoGraphOauthToken -clientId $clientID -clientSecret $clientSecret -tenantID $tenantID
$token = $connection.access_token | ConvertTo-SecureString -AsPlainText -Force 
Connect-MgGraph -AccessToken $token -ErrorAction Stop | Out-Null
Write-Output "Connected to Graph: $((Get-MgContext).AppName)"

# Collect data from EntraID
$allUniqueOwnerValues = ($Scopes.Tag_owner1 + $Scopes.Tag_owner2) | where-object { -not [string]::IsNullOrWhiteSpace($_) } | select-object -unique
$userLookup = @{}
$chunkSize = 15
$userProps = @("DisplayName","UserPrincipalName","AccountEnabled")
for ($i = 0; $i -lt $allUniqueOwnerValues.Count; $i += $chunkSize) {
    # use 0–14 items in one loop, then 15–29 in the next, and so on
    $chunk = $allUniqueOwnerValues[$i..([Math]::Min($i + $chunkSize - 1, $allUniqueOwnerValues.Count - 1))]
    # with the 15 items chunked. Add them to the filter for get-mguser
    $filter = ( $chunk | ForEach-Object { "userPrincipalName eq '$($_.Replace("'", "''"))'" } ) -join " or "
    $users = Get-MgUser -Filter $filter -Property $userProps -All | Where-Object AccountEnabled -eq $true | Select-Object $userProps
    foreach ($user in $users) {
        $userLookup[$user.UserPrincipalName.ToLower()] = $user
    }
}


#------------
# Send Emails
#------------
$emailTargets = [System.Collections.Generic.list[object]]::new() # prepare who to email what in here
foreach ($item in $Scopes) {
    # check if issues persist, build messages for email report
    $messages = @()
    if (-not $item.Tag_owner1) {
        $messages += "$owner1Key tag does not exist"
    }
    elseif (-not $userLookup.ContainsKey($item.Tag_owner1.ToLower())) {
        $messages += "$owner1Key tag does not match an enabled UPN: $($item.Tag_owner1)"
    }
    if (-not $item.Tag_owner2) {
        $messages += "$owner2Key tag does not exist"
    }
    elseif (-not $userLookup.ContainsKey($item.Tag_owner2.ToLower())) {
        $messages += "$owner2Key tag does not match an enabled UPN: $($item.Tag_owner2)"
    }
    if ($item.Tag_owner1 -and $item.Tag_owner2 -and $item.Tag_owner1.ToLower() -eq $item.Tag_owner2.ToLower()) {
        $messages += "$owner1Key and $owner2Key tag value are the same: $($item.Tag_owner1)"
    }

    # Determine who to email based on messages collected and place it in a list
    if ($messages.Count -gt 0) {
        if ($item.Tag_owner1 -and $userLookup.ContainsKey($item.Tag_owner1.ToLower())) {
            $emailTo = $item.Tag_owner1
            $userName = $userLookup[$item.Tag_owner1.ToLower()].DisplayName
        }
        elseif ($item.Tag_owner2 -and $userLookup.ContainsKey($item.Tag_owner2.ToLower())) {
            $emailTo = $item.Tag_owner2
            $userName = $userLookup[$item.Tag_owner2.ToLower()].DisplayName
        }
        else {
            $emailTo = "<adminEmail>"
            $userName = "Admins"
        }
        $emailTargets.Add([pscustomobject]@{
            EmailTo     = $emailTo
            userName    = $userName
            Name        = $item.name
            ResourceId  = $item.ResourceId
            scope       = $item.scope
            Messages    = $messages
        })
    }
}

if($emailTargets.count -eq 0){
    write-output "Job Completed. No anomalies found."
    return 
}

$emailTargetGrouped = $emailTargets | Group-Object EmailTo

#Send Emails out
$clientId = "<clientID>"
$clientName = "<clientName>"
$clientSecret = Get-AzKeyVaultSecret -VaultName $kvName -Name $clientName -AsPlainText
$connection = New-CorpoGraphOauthToken -clientId $clientID -clientSecret $clientSecret -tenantID $tenantID

foreach($email in $emailTargetGrouped){
    write-output "Sending email to $($email.name) for $($email.count) anomalies"
    $tableData = [System.Collections.Generic.List[object]]::new()
    foreach($item in $email.group){
        $tableData.Add([PSCustomObject]@{
            Type = $item.scope
            Name = "<a href='https://portal.azure.com/#@<DOMAIN>/resource/$($item.ResourceId)/tags'>$($item.Name)</a>"
            Issue = "<span style='color:red;'>$($item.messages -join "<br>")</span>"
        }) | Out-Null
    }
    $htmlTable = New-CorpoSimpleHtmlTable -object $tableData
    $htmlText = @"
<p>
Hello $($email.group[0].userName),<br><br>

The following owner tag anomalies have been identified and require your action.<br>

<ul>
    <li>If an owner tag does not exist: <b>Create it</b></li>
    <li>If an owner tag exists but does not contain a valid UPN in EntraID: <b>Update it</b></li>
</ul>

<b>Note:</b> If a user has left the organization (account disabled or deleted), 
they will appear as <i>'tag does not match an enabled UPN'</i> and must be replaced.<br>
</p>
"@
    $emailParams = @{
        Token       = $connection
        From        = "<FromEmail>"
        To          = $email.name
        Subject     = "Azure Services OwnerTag Issues [$((Get-Date).ToString('yyyy/MM/dd'))]"
        Body        = ( $htmlText + $htmlTable )
        HTMLBody    = $true
        Importance  = $true
    }
    Send-CorpoGraphMail @emailParams | out-null
}