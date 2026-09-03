<#  
    Example of Exchange RBAC to send emails as one account
    - With a service principal in Entra (App Registration and/or managed identity)
    - Plus a shared mailbox you want to send email as
    - Run the Following
#>

#--- AuthN
# Install-Module ExchangeOnlineManagement
Connect-ExchangeOnline 

#--- Variables
$spName     = "<NAME OF SERVICE PRINCIPAL>"
$spAppId    = "<APPLICATION/CLIENT ID OF SERVICE PRINCIPAL>"
$spObjectId = "<OBJECT ID OF SERVICE PRINCIPAL>"
$scope = "no-reply@company.com"
$role = "Application Mail.Send"

#--- Create Service Principal
New-ServicePrincipal -AppId $spAppId -DisplayName $spName -ObjectId $spObjectId

#--- Scope
New-ManagementScope -Name $scope -RecipientRestrictionFilter "EmailAddresses -eq '$scope'"

#--- Assign Role
New-ManagementRoleAssignment -Name "$spName MailSend $scope" -App $spObjectId -Role $role -CustomResourceScope $scope

#--- Others Commands
get-ServicePrincipal  # Get all service Principals you made
get-ManagementScope # Get all scopes you made
Get-Recipient -RecipientPreviewFilter "EmailAddresses -eq '$scope'" # Practice building a scope with this cmdlet before using one. The outputed item(s) are what will get the permissions
Get-ManagementRole | Where-Object Name -Like "Application*" | Format-Table Name, Description # Collect Roles
Get-ManagementRoleAssignment -RoleAssigneeType "ServicePrincipal" # See all assignments
Test-ServicePrincipalAuthorization -Identity $spObjectId -Resource "no-reply@company.com" # Test Assignment
