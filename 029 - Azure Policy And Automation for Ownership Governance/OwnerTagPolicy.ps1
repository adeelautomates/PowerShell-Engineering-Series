# Be sure to connect via Az Module First
# connect-azaccount

#----POLICY FOR RESOURCE
# policy for resources taking tags from resource groups if they dont have it
$policy = @"
{
  "properties": {
    "displayName": "Inherit owner1 and owner2 tags from resource group if missing",
    "policyType": "Custom",
    "mode": "Indexed",
    "description": "Adds owner1 and owner2 tags from the parent resource group when missing on resources.",
    "metadata": {
      "version": "1.0.0",
      "category": "Tags"
    },
    "parameters": {
      "owner1TagName": {
        "type": "String",
      },
      "owner2TagName": {
        "type": "String",
      }
    },
    "policyRule": {
      "if": {
        "anyOf": [
          {
            "allOf": [
              {
                "field": "[concat('tags[', parameters('owner1TagName'), ']')]",
                "exists": "false"
              },
              {
                "value": "[resourceGroup().tags[parameters('owner1TagName')]]",
                "notEquals": ""
              }
            ]
          },
          {
            "allOf": [
              {
                "field": "[concat('tags[', parameters('owner2TagName'), ']')]",
                "exists": "false"
              },
              {
                "value": "[resourceGroup().tags[parameters('owner2TagName')]]",
                "notEquals": ""
              }
            ]
          }
        ]
      },
      "then": {
        "effect": "modify",
        "details": {
          "roleDefinitionIds": [
            "/providers/microsoft.authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
          ],
          "operations": [
            {
              "operation": "add",
              "field": "[concat('tags[', parameters('owner1TagName'), ']')]",
              "value": "[resourceGroup().tags[parameters('owner1TagName')]]"
            },
            {
              "operation": "add",
              "field": "[concat('tags[', parameters('owner2TagName'), ']')]",
              "value": "[resourceGroup().tags[parameters('owner2TagName')]]"
            }
          ]
        }
      }
    }
  }
}
"@

$owner1Key = "Owner1"
$owner2Key = "Owner2"
$name =  "Corpo Inherit Owner Tags From Resource Group If Missing"
$shortName = "crpInhRGOwnTags" # must be less than 24 characters
$scope = "corpo"

$definitionParams = @{
    DisplayName = $name
    Name = $name -replace " ", ""
    policy = $policy
    ManagementGroupName = $scope
}
$definition = New-AzPolicyDefinition @definitionParams


$assignmentParams = @{
    DisplayName = $name
    Name = $shortName
    PolicyDefinition = $definition
    Scope = "/providers/Microsoft.Management/managementGroups/$scope"
    PolicyParameterObject = @{
        owner1TagName = $owner1Key
        owner2TagName = $owner2Key
    }
    IdentityType = "SystemAssigned" # needed for any modifying policies, I am using systemAssigned of the assignment
    Location = "global"
}
New-AzPolicyAssignment @assignmentParams


#----POLICY FOR RESOURCE GROUP
# policy for ResourceGroup being blocked unless they have valid tags or are excluded
$policy = @"
{
  "displayName": "Require owner1 and owner2 tags on resource groups",
  "policyType": "Custom",
  "mode": "All",
  "description": "Require owner1 and owner2 tags on resource groups",
  "metadata": {
    "version": "1.0.0",
    "category": "Tags"
  },
  "parameters": {
    "owner1TagName": {
      "type": "String"
    },
    "owner2TagName": {
      "type": "String"
    },
    "excludedList": {
      "type": "Array",
      "defaultValue": []
    }
  },
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Resources/subscriptions/resourceGroups"
        },
        {
          "field": "name",
          "notContains": "ignore"
        },
        {
          "field": "name",
          "notLike": "rg-special*"
        },
        {
          "field": "name",
          "notIn": "[parameters('excludedList')]"
        },
        {
          "anyOf": [
            {
              "field": "[concat('tags[', parameters('owner1TagName'), ']')]",
              "exists": "false"
            },
            {
              "field": "[concat('tags[', parameters('owner2TagName'), ']')]",
              "exists": "false"
            }
          ]
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  }
}
"@


$owner1Key = "owner1" 
$owner2Key = "owner2"
$name = "Corpo Require Owner Tags On Resource Groups"
$shortName = "crpReqOwnRGTags" # must be less than 24 characters
$scope = "corpo" # Requires RBAC: At least Resource Policy Contributor at this scope to assign policies.

$definitionParams = @{
    DisplayName         = $name
    Name                = $name -replace " ", ""
    Policy              = $policy
    ManagementGroupName = $scope
}
$definition = New-AzPolicyDefinition @definitionParams



$assignmentParams = @{
    DisplayName           = $name
    Name                  = $shortName
    PolicyDefinition      = $definition
    Scope                 = "/providers/Microsoft.Management/managementGroups/$scope"
    PolicyParameterObject = @{
        owner1TagName = $owner1Key
        owner2TagName = $owner2Key
        excludedList  = @(
            # RGs I want to exclude (maybe some deployments creates them)
            "rg-example-excluded-001"
            "rg-example-excluded-002"
             # Azure system / special RGs
            "NetworkWatcherRG"
            "DefaultResourceGroup"
            "ResourceMoverRG"
        )
    }
    NonComplianceMessage  = @(
        @{ Message = "Please Add both Owner Tags to Resource Groups ($owner1Key & $owner2Key). Values must be EntraID UPNs of existing users" }
    )
}
New-AzPolicyAssignment @assignmentParams



