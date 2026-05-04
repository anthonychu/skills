targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment used to generate a unique hash for resource names.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@description('GitHub Personal Access Token with Copilot Requests permission.')
@secure()
@minLength(1)
param githubToken string

@description('GitHub Copilot model to use.')
param copilotModel string = 'claude-opus-4.6'

// ──────────────────────────────────────────────
// Add app-specific parameters below as needed.
// Example: param toEmail string
// ──────────────────────────────────────────────

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = '${abbrs.webSitesFunctions}copilot-func-${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'
var sessionShareName = 'code-assistant-session'
var deployerPrincipalId = deployer().objectId

// ─── Resource Group ───
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// ─── Managed Identity ───
module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: '${abbrs.managedIdentityUserAssignedIdentities}copilot-func-${resourceToken}'
  }
}

// ─── App Service Plan (Flex Consumption) ───
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

// ─── Storage Account ───
module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [{ name: deploymentStorageContainerName }]
    }
    fileServices: {
      shares: [{ name: sessionShareName, shareQuota: 1 }]
    }
    minimumTlsVersion: 'TLS1_2'
    location: location
    tags: tags
  }
}

// ─── Function App ───
module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.12'
    storageAccountName: storage.outputs.name
    deploymentStorageContainerName: deploymentStorageContainerName
    sessionShareName: sessionShareName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    appSettings: {
      GITHUB_TOKEN: githubToken
      COPILOT_MODEL: copilotModel
      AZURE_CLIENT_ID: apiUserAssignedIdentity.outputs.clientId
      ENABLE_MULTIPLATFORM_BUILD: 'true'
      PYTHON_ENABLE_INIT_INDEXING: '1'
      // ── Add app settings for session pool, connectors, etc. ──
      // ACA_SESSION_POOL_ENDPOINT: sessionPool.outputs.poolManagementEndpoint
      // O365_CONNECTION_ID: office365Connection.outputs.connectionId
      // TO_EMAIL: toEmail
    }
  }
}

// ─── RBAC (Storage + App Insights) ───
module rbac './app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
  }
}

// ─── ACA Session Pool ──────────────────────────
// Uncomment if the agent uses execution_sandbox.
//
// module sessionPool './app/session-pool.bicep' = {
//   name: 'sessionPool'
//   scope: rg
//   params: {
//     sessionPoolName: 'sessionpool${resourceToken}'
//     location: location
//     tags: tags
//   }
// }
//
// module sessionPoolRbac './app/session-pool-rbac.bicep' = {
//   name: 'sessionPoolRbac'
//   scope: rg
//   dependsOn: [sessionPool]
//   params: {
//     sessionPoolName: 'sessionpool${resourceToken}'
//     managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
//     userPrincipalId: deployerPrincipalId
//   }
// }

// ─── Connectors ────────────────────────────────
// Uncomment if the agent uses tools_from_connections.
// Change 'office365' to match your connector type.
//
// var connectionName = 'office365-${resourceToken}'
//
// module office365Connection './app/office365-connection.bicep' = {
//   name: 'office365Connection'
//   scope: rg
//   params: {
//     connectionName: connectionName
//     location: location
//     tags: tags
//   }
// }
//
// module connectorRbac './app/connector-rbac.bicep' = {
//   name: 'connectorRbac'
//   scope: rg
//   dependsOn: [office365Connection]
//   params: {
//     connectionName: connectionName
//     managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
//   }
// }

// ─── Monitoring ───
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}

module monitoring 'br/public:avm/res/insights/component:0.4.1' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

// ─── Outputs ───
output AZURE_LOCATION string = location
output AZURE_FUNCTION_NAME string = api.outputs.SERVICE_API_NAME
// output O365_CONNECTION_NAME string = connectionName
