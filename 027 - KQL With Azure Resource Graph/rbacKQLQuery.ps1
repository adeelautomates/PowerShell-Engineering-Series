$query = @"
authorizationresources
| where type =~ "microsoft.authorization/roleassignments" // Get Data from RBAC table for Role Assignments
| extend principalType = tostring(properties.principalType) // Store PrincipalType here
| extend assignmentScope = tostring(properties.scope) // Store Scope (aka resource ID)
| extend // this extend is separate as the previous extends need to be calculated before we can pull them together
    roleId = tolower(tostring(properties.roleDefinitionId)), // Get the Role Definition ID (Owner, Contributor, etc as ID)
    // extract = function that pulls a value from text using regex, we use it to store these depending on what it is
    subId = extract(@"^/subscriptions/([^/]+)", 1, assignmentScope), // Grabs the value right after /subscriptions/
    mgId = extract(@"^/providers/Microsoft\.Management/managementGroups/([^/]+)", 1, assignmentScope), // Only works if scope starts with a management group path
    rgName = extract(@"/resourceGroups/([^/]+)", 1, assignmentScope), // Finds /resourceGroups/... anywhere in the string and grabs what is right after
    itemName = extract(@"/([^/]+)$", 1, assignmentScope), // Finds whatever comes after the last /
    // if else statement to set the type to one of the following: mg, sub, rg or resource
    scopeKind = case(
        assignmentScope matches regex @"^/providers/Microsoft\.Management/managementGroups/[^/]+$", "Management Group",
        assignmentScope matches regex @"^/subscriptions/[^/]+$", "Subscription",
        assignmentScope matches regex @"^/subscriptions/[^/]+/resourceGroups/[^/]+$", "Resource Group",
        "Resource"
    )
// project the data we transformed thus far for future tables
| project principalId = tostring(properties.principalId),
          principalType,
          roleId,
          assignmentScope,
          scopeKind,
          mgId,
          subId,
          rgName,
          itemName
// join the same table as before but this time lets look in roledefinitions
// use the roleId from the previous table to now get its name
| join kind=leftouter (
    authorizationresources
    | where type =~ "microsoft.authorization/roledefinitions"
    | project roleId = tolower(tostring(id)),
              roleName = tostring(properties.roleName)
) on roleId
// go to resourcecontainers as unlike mg, rg and resource we got their names
// but for sub we only got the ID, so lets get the subscription name
| join kind=leftouter (
    resourcecontainers
    | where type =~ "microsoft.resources/subscriptions"
    | project subId = tostring(subscriptionId),
              subName = tostring(name)
) on subId
// set scopeName whether it is the mg, sub, rg or resource name
| extend scopeName = case(
    scopeKind == "Management Group", mgId,
    scopeKind == "Subscription", subName,
    scopeKind == "Resource Group", rgName,
    itemName
)
// project final data and sort it
| project identityType = principalType,
          identityId = principalId,
          role = roleName,
          scopeType = scopeKind,
          scopeName
| order by scopeType asc, scopeName asc
"@ 

$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token | ConvertFrom-SecureString -AsPlainText
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}
$uri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2024-04-01"
$rbacQueryAll = [System.Collections.Generic.List[object]]::new()
$skipToken = $null
do {
    $bodyObject = @{
        query         = $query
        subscriptions = @()  # OK for tenant-wide / MG scopes
        options       = @{
            resultFormat = "objectArray"
            top          = 1000
        }
    }
    if ($skipToken) {
        $bodyObject.options.skipToken = $skipToken
    }
    $body = $bodyObject | ConvertTo-Json -Depth 50
    $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body
    if ($response.data) {
        $rbacQueryAll.AddRange([object[]]$response.data)
    }

    $skipToken = $response.skipToken
}
while ($skipToken)
$rbacQueryAll | Format-Table