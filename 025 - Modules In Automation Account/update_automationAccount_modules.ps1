#--------------------
# Initalize Variables
#--------------------
# Automation Account Details + URI Prefix
$automationAccount       = "<automationAccoutName"
$subID                   = "<subID>"
$resourceGroup           = "<rgName>"
$location                = "<region>"
$runtimeName             = "Automate-PowerShell-$((get-date).toString("yyyymmdd"))"
$uriPrefix = "https://management.azure.com/subscriptions/$($subID)/resourceGroups/$($resourceGroup)/providers/Microsoft.Automation/automationAccounts/$($automationAccount)/runtimeEnvironments/$($runtimeName)"

# PowerShell Gallery Modules
$galleryModules = @(
    #OTHER MODULES
    "ImportExcel"
    "Microsoft.Graph"
    "Az"
    # AZURE SUBMODULES https://www.powershellgallery.com/packages/Az/15.3.0
    "Az.Accounts"
    "Az.Advisor"
    "Az.Aks"
    "Az.AnalysisServices"
    "Az.ApiManagement"
    "Az.App"
    "Az.AppConfiguration"
    "Az.ApplicationInsights"
    "Az.ArcResourceBridge"
    "Az.ArizeAI"
    "Az.Attestation"
    "Az.Automanage"
    "Az.Automation"
    "Az.Batch"
    "Az.Billing"
    "Az.Cdn"
    "Az.CloudService"
    "Az.CognitiveServices"
    "Az.Compute"
    "Az.ConfidentialLedger"
    "Az.ConnectedMachine"
    "Az.ContainerInstance"
    "Az.ContainerRegistry"
    "Az.CosmosDB"
    "Az.DataBoxEdge"
    "Az.Databricks"
    "Az.DataFactory"
    "Az.DataLakeAnalytics"
    "Az.DataLakeStore"
    "Az.DataMigration"
    "Az.DataProtection"
    "Az.DataShare"
    "Az.DataTransfer"
    "Az.DesktopVirtualization"
    "Az.DevCenter"
    "Az.DeviceRegistry"
    "Az.DevTestLabs"
    "Az.Dns"
    "Az.DnsResolver"
    "Az.ElasticSan"
    "Az.EventGrid"
    "Az.EventHub"
    "Az.Fabric"
    "Az.FirmwareAnalysis"
    "Az.FrontDoor"
    "Az.Functions"
    "Az.HDInsight"
    "Az.HealthcareApis"
    "Az.HealthDataAIServices"
    "Az.IotHub"
    "Az.KeyVault"
    "Az.Kusto"
    "Az.LambdaTest"
    "Az.LoadTesting"
    "Az.LogicApp"
    "Az.MachineLearning"
    "Az.MachineLearningServices"
    "Az.Maintenance"
    "Az.ManagedServiceIdentity"
    "Az.ManagedServices"
    "Az.MarketplaceOrdering"
    "Az.Migrate"
    "Az.Monitor"
    "Az.MySql"
    "Az.NetAppFiles"
    "Az.Network"
    "Az.NetworkCloud"
    "Az.Nginx"
    "Az.NotificationHubs"
    "Az.OperationalInsights"
    "Az.Oracle"
    "Az.PolicyInsights"
    "Az.PostgreSql"
    "Az.PowerBIEmbedded"
    "Az.PrivateDns"
    "Az.RecoveryServices"
    "Az.RedisCache"
    "Az.RedisEnterpriseCache"
    "Az.Relay"
    "Az.ResourceGraph"
    "Az.ResourceMover"
    "Az.Resources"
    "Az.Security"
    "Az.SecurityInsights"
    "Az.ServiceBus"
    "Az.ServiceFabric"
    "Az.SignalR"
    "Az.Sql"
    "Az.SqlVirtualMachine"
    "Az.StackHCI"
    "Az.StackHCIVM"
    "Az.Storage"
    "Az.StorageAction"
    "Az.StorageDiscovery"
    "Az.StorageMover"
    "Az.StorageSync"
    "Az.StreamAnalytics"
    "Az.Support"
    "Az.Synapse"
    "Az.TrafficManager"
    "Az.Websites"
    "Az.Workloads"
    #GRAPH SUBMODULES https://www.powershellgallery.com/packages/Microsoft.Graph/2.25.0
    "Microsoft.Graph.Applications"
    "Microsoft.Graph.Authentication"
    "Microsoft.Graph.BackupRestore"
    "Microsoft.Graph.Bookings"
    "Microsoft.Graph.Calendar"
    "Microsoft.Graph.ChangeNotifications"
    "Microsoft.Graph.CloudCommunications"
    "Microsoft.Graph.Compliance"
    "Microsoft.Graph.CrossDeviceExperiences"
    "Microsoft.Graph.DeviceManagement"
    "Microsoft.Graph.DirectoryObjects"
    "Microsoft.Graph.Education"
    "Microsoft.Graph.Files"
    "Microsoft.Graph.Groups"
    "Microsoft.Graph.Mail"
    "Microsoft.Graph.Notes"
    "Microsoft.Graph.People"
    "Microsoft.Graph.PersonalContacts"
    "Microsoft.Graph.Planner"
    "Microsoft.Graph.Reports"
    "Microsoft.Graph.SchemaExtensions"
    "Microsoft.Graph.Search"
    "Microsoft.Graph.Security"
    "Microsoft.Graph.Sites"
    "Microsoft.Graph.Teams"
    "Microsoft.Graph.Users"
    "Microsoft.Graph.Devices.CorporateManagement"
    "Microsoft.Graph.Devices.CloudPrint"
    "Microsoft.Graph.Identity.Partner"
    "Microsoft.Graph.Identity.SignIns"
    "Microsoft.Graph.Devices.ServiceAnnouncement"
    "Microsoft.Graph.Identity.DirectoryManagement"
    "Microsoft.Graph.Identity.Governance"
    "Microsoft.Graph.Users.Actions"
    "Microsoft.Graph.Users.Functions"
    "Microsoft.Graph.DeviceManagement.Actions"
    "Microsoft.Graph.DeviceManagement.Administration"
    "Microsoft.Graph.DeviceManagement.Enrollment"
    "Microsoft.Graph.DeviceManagement.Functions"
)

# Storage Account Where Your Module Files Sit 
$storageAccount = "<saName>"
$container      = "<containerName"
$storageModules          = @(
    "Corpo.CoreFunctionLibrary.zip"
)

# Generate Token
$RetrieveToken = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
$token = $RetrieveToken.Token -is [securestring] ? ($RetrieveToken.Token | ConvertFrom-SecureString -AsPlainText) : $RetrieveToken.Token
$headers = @{
    Authorization  = "Bearer $token"
    "Content-Type" = "application/json"
}


#---------------
# Create Runtime
#---------------
$body = @{
    location = $location
    properties = @{
        description = "Created by Automation On $(Get-Date -Format s)"
        runTime = @{
            language = "PowerShell"
            version = "7.4"
        }

    }
} | ConvertTo-Json -Depth 10
$runtimeUri = $uriPrefix + "?api-version=2024-10-23"
$response = invoke-restmethod -headers $headers -method Put -Uri $runtimeUri -body $body 
write-output "Created/Selected Runtime Environment: $($response.name)"

#------------------------------------
# Add Modules from PowerShell Gallery
#------------------------------------
foreach($module in $galleryModules){
    $galleryUri = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$module' and IsLatestVersion"
    $id = (Invoke-RestMethod -Uri $galleryUri -Method Get).id # this ID is a url that provides the version
    $version = ( ($id -split "Version='")[1] -split "'" )[0]

    $body = @{
        properties = @{
            contentLink = @{
                uri = "https://www.powershellgallery.com/api/v2/package/$module/$version" # this format is needed to upload file to automation account
            }
        }
    } | convertTo-Json -Depth 5

    $moduleUpdateUri = $uriPrefix + "/packages/$module/?api-version=2024-10-23"
    $success = $false
    while (-not $success) {
        try {
            Invoke-RestMethod -Headers $headers -Method PUT -Uri $moduleUpdateUri -body $body -ErrorAction Stop | out-null
            Write-Output "- Added / Updated Module : $module"
            $success = $true
        }
        catch {
            $status = $_
            if($status.Exception.Response.StatusCode.Value__ -eq 429){
                write-warning "- Automation Import Queue Full. Waiting 30 seconds..."
                start-sleep -Seconds 30
            }
            else{
                write-output "- Unable to find Module : $module. Skipping: $status"
                break
            }
        }
    }
}


#-------------------------------------------
# Add Modules From Storage Account using SaS
#-------------------------------------------
# note you might need to switch sub to SA if not already in it
$ctx = New-AzStorageContext -StorageAccountName $storageAccount -UseConnectedAccount
foreach($blob in $storageModules){
    $module = $blob -replace ".zip", "" # store name without .zip
    $sasUri = New-AzStorageBlobSASToken -Context $ctx -Container $container -blob $blob -Permission r -ExpiryTime (Get-Date).AddHours(1) -FullUri
    $body = @{
        properties = @{
            contentLink = @{
                uri = $sasUri # add the sasUri here. since we cant add tokens we cant do this identity based.
            }
        }
    } | convertTo-Json -Depth 5
    # Add Module from Storage Account to the runtime in Automation Account
    $moduleUpdateUri = $uriPrefix + "/packages/$module/?api-version=2024-10-23"
    $success = $false
    while (-not $success) {
        try {
            Invoke-RestMethod -Headers $headers -Method PUT -Uri $moduleUpdateUri -body $body -ErrorAction Stop | out-null
            Write-Output "- Added / Updated Module : $module"
            $success = $true
        }
        catch {
            $status = $_
            if($status.Exception.Response.StatusCode.Value__ -eq 429){
                write-warning "- Automation Import Queue Full. Waiting 30 seconds..."
                start-sleep -Seconds 30
            }
            else{
                write-output "- Unable to find Module : $module. Skipping: $status"
                break
            }
        }
    }
}