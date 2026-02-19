#---Function To Get OAuth Token For API Calls---#
function New-SimpleGraphOauthToken {
    param (
        [Parameter(Mandatory = $true)] 
            $ClientId,
        [Parameter(Mandatory = $true)] 
            $ClientSecret,
        [Parameter(Mandatory = $true)] 
            $TenantID
    )
    $body = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    $uri = "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"
    $token = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ErrorAction Stop
    return $token
}

#---Call Function---#
$clientID = "<ID>"
$clientSecret = Get-AzKeyVaultSecret -VaultName "<KVNAME>" -Name "<SECRETNAME>" -AsPlainText
$tenantID = Get-AzKeyVaultSecret -VaultName "<KVNAME>" -Name "<SECRETNAME>" -AsPlainText

$token = New-SimpleGraphOauthToken -clientId $clientID -clientSecret $clientSecret -tenantID $tenantID
$token.access_token


#---Run Graph Query as this Account---#
$headers = @{
    "Authorization" = "Bearer $($token.access_token)"
    "Content-Type"  = "application/json"
}
$uri = "https://graph.microsoft.com/v1.0/groups"
$groups = Invoke-RestMethod -Method "GET" -headers $headers -uri $uri
$groups.value | select-object id, displayName



#---Build a Class for Microsoft Platforms Token Generation---#
class CorpoOauthClient {
    # Instance Properties (including hidden ones)
    [guid]$ClientID
    hidden [string]$ClientSecret
    [guid]$TenantID
    [string]$ScopeURL
    hidden [string]$AccessToken
    hidden [dateTime]$ExpiresOnUtc

    # Static Property (Something for the class itself to use, not us directly)
    hidden static [hashtable]$ScopeOptions = @{
        graph = "https://graph.microsoft.com/.default"
        azure   = "https://management.azure.com/.default"
        storage = "https://storage.azure.com/.default"
    }

    # Static Method (Something you can run against the class itself)
    static [pscustomobject[]] GetScopeOptions() {
        return [CorpoOauthClient]::ScopeOptions.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{
                ValueProvided     = $_.Key
                ValueSet          = $_.Value
            }
        }
    }

    # Constructor (Something that instanites the object with the values we provide)
    CorpoOauthClient([guid]$clientID, [string]$clientSecret, [guid]$tenantID, [string]$scope){
        $this.ClientID = $clientID
        $this.ClientSecret = $clientSecret
        $this.TenantID = $tenantID

        $scopeKey = $scope.ToLower().Trim()
        if( -not [CorpoOauthClient]::ScopeOptions.ContainsKey($scopeKey) ){
            throw "Scope must be one of: $( ([CorpoOauthClient]::ScopeOptions.Keys) -join ', '). You entered: '$scope'"
        }
        $this.ScopeURL = [CorpoOauthClient]::ScopeOptions[$scopeKey]
    }

    # Instance Method (Something you can run against the object that gets instaniated)
    [pscustomobject] Token(){
        #----Reuse Token----#
        # If we already have a token and its NOT expiring soon(10 minutes), reuse it
        if ( $this.AccessToken -and ([dateTime]::UtcNow.AddMinutes(10) -lt $this.ExpiresOnUtc) ){
            return [pscustomobject]@{
                ScopeUrl        = $this.ScopeUrl
                ExpiresOnUtc    = $this.ExpiresOnUtc
                AccessToken     = $this.AccessToken
            }
        }

        #---Make API Call to Generate Token---#
        $body = @{
            client_id     = $this.ClientId
            scope         = $this.ScopeURL
            client_secret = $this.ClientSecret
            grant_type    = "client_credentials"
        }
        $uri = "https://login.microsoftonline.com/$($this.TenantId)/oauth2/v2.0/token"
        $token = Invoke-RestMethod -Uri $uri -Method POST -Body $body

        #---Cutomize Output---#
        $this.AccessToken = $token.access_token
        $this.ExpiresOnUtc = [datetime]::UtcNow.AddSeconds([int]$token.expires_in)
        return [pscustomobject]@{
            ScopeUrl = $this.ScopeURL
            ExpiresOnUtc = $this.ExpiresOnUtc
            AccessToken = $this.AccessToken
        }
    }
}

# RUN STATIC METHOD to see scopes
[CorpoOauthClient]::GetScopeOptions()

# Instaniate the Class
$graphClient = [CorpoOauthClient]::new(
    "<ID>",
    (Get-AzKeyVaultSecret -VaultName "<KVNAME>" -Name "<SECRETNAME>" -AsPlainText),
    (Get-AzKeyVaultSecret -VaultName "<KVNAME>" -Name "<SECRETNAME>" -AsPlainText),
    "graph"
)
$graphClient | get-member
$graphClient.token()

# Run using this token method approach with a refresh process backed into it's class
$headers = @{
    "Authorization" = "Bearer $( $graphClient.token().AccessToken )"
    "Content-Type"  = "application/json"
}
$uri = "https://graph.microsoft.com/v1.0/groups"
$groups = Invoke-RestMethod -Method "GET" -headers $headers -uri $uri
$groups.value | select-object id, displayName



#---Bonus 1: Class Inheritenace---#
class CorpoGraphClient : CorpoOauthClient {
    CorpoGraphClient($clientId, $clientSecret, $tenantID) : base($clientID, $clientSecret, $tenantID, "graph") {}
    [pscustomobject] GetAllGroups(){
        $token = $this.Token()
        $headers = @{
            "Authorization" = "Bearer $( $token.AccessToken )"
            "Content-Type"  = "application/json"
        }
        return Invoke-RestMethod -Method "GET" -Uri "https://graph.microsoft.com/v1.0/groups" -Headers $headers
    }
}

$graph = [CorpoGraphClient]::new(
    "<ID>",
    (Get-AzKeyVaultSecret -VaultName "<KVNAME" -Name "<SECRETNAME>" -AsPlainText),
    (Get-AzKeyVaultSecret -VaultName "<KVNAME" -Name "<SECRETNAME>" -AsPlainText)
)
$graph.GetAllGroups()


#---Bonus 2: Using Enums---#
enum Endpoint {
    users
    groups
    servicePrincipals
}
class CorpoGraphClientWithEnums : CorpoOauthClient {
    CorpoGraphClientWithEnums($clientId, $clientSecret, $tenantID) : base($clientID, $clientSecret, $tenantID, "graph") {}
    [pscustomobject] GetData( [Endpoint]$endpoint ){
        $token = $this.Token()
        $headers = @{
            "Authorization" = "Bearer $( $token.AccessToken )"
            "Content-Type"  = "application/json"
        }
        return Invoke-RestMethod -Method "GET" -Uri "https://graph.microsoft.com/v1.0/$($endpoint.ToString())" -Headers $headers
    }
}

$graph = [CorpoGraphClientWithEnums]::new(
    "<ID>",
    (Get-AzKeyVaultSecret -VaultName "<KVNAME>" -Name "<SECRETNAME>" -AsPlainText),
    (Get-AzKeyVaultSecret -VaultName "<KVNAME>" -Name "<SECRETNAME>" -AsPlainText)
)

$graph.GetData([Endpoint]::users)
$graph.GetData([Endpoint]::groups)
$graph.GetData([Endpoint]::servicePrincipals)



#---Bonus 3: Script Logging---#
enum LogLevel { Info; Warn; Error }
class CorpoLogger {
    [System.Collections.Generic.List[pscustomobject]]$Entries

    # you can set a new instance without any arguments like so while still having actions being taken
    CorpoLogger() {
        $this.Entries = [System.Collections.Generic.List[pscustomobject]]::new()
    }

    # these methods are used to log items in a simple way (versus $log.Log([LogLevel]::Info, "Starting run")
    [void] Info([string]$message)  { $this.Log([LogLevel]::Info,  $message) }
    [void] Warn([string]$message)  { $this.Log([LogLevel]::Warn,  $message) }
    [void] Error([string]$message) { $this.Log([LogLevel]::Error, $message) }

    # This method will fill out the log properly. Including time stamp (and whatever else you want to add)
    [void] Log([LogLevel]$type, [string]$message) {
        $this.Entries.Add([pscustomobject]@{
            Type    = $type.ToString()
            Time    = [datetime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
            Message = $message
        })
    }
}

#---Output---#
$log = [CorpoLogger]::new()
$log.Info("Starting Job")
start-sleep -seconds 2
$log.Warn("Paging detected")
Start-Sleep -Seconds 2
$log.Info("Completed first task")
Start-Sleep -Seconds 2
$log.Info("Starting Second Task")
$log.Error("Graph request failed: 403 Forbidden. Ending Script")

$log.entries | Sort-Object Time | Export-Csv -Path "c:\test\ScriptLogs.csv" -NoTypeInformation
