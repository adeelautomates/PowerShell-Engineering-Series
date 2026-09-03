#--- AuthN
# Install-Module ExchangeOnlineManagement
Connect-ExchangeOnline 

#--- Variables
$spName     = "la-test-email-001"
$spAppId    = "fa1a5704-2692-4738-b2d2-7bb7611f6f67"
$spObjectId = "387d71d1-3744-4a8d-8fb6-604422ff62c4"
$scope = "corpo-automation@lb4s.onmicrosoft.com"
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
Test-ServicePrincipalAuthorization -Identity $spObjectId -Resource "corpo-automation@lb4s.onmicrosoft.com" # Test Assignment
