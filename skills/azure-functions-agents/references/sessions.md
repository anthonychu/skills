# ACA Dynamic Sessions Reference

Azure Container Apps (ACA) Dynamic Sessions provide sandboxed Python code execution for
agents via the `execute_python` tool. Sessions support Playwright for web browsing/automation.

## How It Works

When `execution_sandbox` is configured in an agent, the framework creates an `execute_python`
tool that runs Python code in a persistent Jupyter kernel hosted in an ACA session pool.

- Each Copilot session gets a unique ACA session
- Variables, imports, and files persist across tool calls within the same session
- Sessions include Playwright for browser automation (screenshots, DOM extraction)
- Files can be written to `/mnt/data/` (persistent within the session)

## Configuring in Agent Files

```yaml
---
name: My Agent
execution_sandbox:
  session_pool_management_endpoint: $ACA_SESSION_POOL_ENDPOINT
---

You can use execute_python to run Python code.
```

The `ACA_SESSION_POOL_ENDPOINT` env var should point to the session pool's management endpoint,
e.g., `https://eastus2.dynamicsessions.io/subscriptions/{sub}/resourceGroups/{rg}/sessionPools/{pool-name}`

## Creating a Session Pool

### Via Bicep (recommended — deploy with `azd up`)

```bicep
// session-pool.bicep
param sessionPoolName string
param location string
param tags object = {}

resource sessionPool 'Microsoft.App/sessionPools@2025-01-01' = {
  name: sessionPoolName
  location: location
  tags: tags
  properties: {
    containerType: 'PythonLTS'
    poolManagementType: 'Dynamic'
    dynamicPoolConfiguration: {
      lifecycleConfiguration: {
        lifecycleType: 'Timed'
        cooldownPeriodInSeconds: 300
      }
    }
    scaleConfiguration: {
      maxConcurrentSessions: 100
      readySessionInstances: 0
    }
    sessionNetworkConfiguration: {
      status: 'EgressEnabled'
    }
  }
}

output sessionPoolId string = sessionPool.id
output poolManagementEndpoint string = sessionPool.properties.poolManagementEndpoint
```

### Via Azure CLI

```bash
az containerapp sessionpool create \
  --name {pool-name} \
  --resource-group {rg} \
  --location {location} \
  --container-type PythonLTS \
  --max-sessions 100 \
  --network-status EgressEnabled \
  --cooldown-period 300
```

### Reusing an Existing Session Pool

If a session pool already exists (e.g., from a previous deployment), you can reuse it:

1. Find the pool's management endpoint:
   ```bash
   az containerapp sessionpool show \
     --name {pool-name} \
     --resource-group {rg} \
     --query properties.poolManagementEndpoint -o tsv
   ```

2. Set the endpoint in your `local.settings.json` or Bicep app settings:
   ```json
   {
     "ACA_SESSION_POOL_ENDPOINT": "https://eastus2.dynamicsessions.io/subscriptions/..."
   }
   ```

3. Ensure the identity has the Session Executor role (see RBAC below).

## RBAC — Session Executor Role

The **Azure ContainerApps Session Executor** role (`0fb8eba5-a2bb-4abe-b1c1-49dfad359bb0`)
is required for any identity that needs to run code in the session pool.

### For the deployed app (managed identity)

```bicep
// session-pool-rbac.bicep
param sessionPoolName string
param managedIdentityPrincipalId string
param userPrincipalId string = ''

var sessionExecutorRoleId = '0fb8eba5-a2bb-4abe-b1c1-49dfad359bb0'

resource sessionPool 'Microsoft.App/sessionPools@2025-01-01' existing = {
  name: sessionPoolName
}

// For the managed identity (deployed function app)
resource sessionPoolRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sessionPool.id, managedIdentityPrincipalId, sessionExecutorRoleId)
  scope: sessionPool
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', sessionExecutorRoleId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// For the deployer's identity (local development)
resource sessionPoolUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userPrincipalId)) {
  name: guid(sessionPool.id, userPrincipalId, sessionExecutorRoleId)
  scope: sessionPool
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', sessionExecutorRoleId)
    principalId: userPrincipalId
    principalType: 'User'
  }
}
```

### For local development (your user identity)

```bash
# Get your user object ID
USER_OID=$(az ad signed-in-user show --query id -o tsv)

# Assign Session Executor role
az role assignment create \
  --assignee "$USER_OID" \
  --role "Azure ContainerApps Session Executor" \
  --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/sessionPools/{pool-name}"
```

### Verifying role assignment

```bash
az role assignment list \
  --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/sessionPools/{pool-name}" \
  --query "[].{principal:principalId, role:roleDefinitionName}" -o table
```

## Integration with Bicep Infrastructure

When deploying the full app, wire the session pool into `main.bicep`:

```bicep
// Create the session pool
module sessionPool './app/session-pool.bicep' = {
  name: 'sessionPool'
  scope: rg
  params: {
    sessionPoolName: 'sessionpool${resourceToken}'
    location: location
    tags: tags
  }
}

// Assign RBAC
module sessionPoolRbac './app/session-pool-rbac.bicep' = {
  name: 'sessionPoolRbac'
  scope: rg
  dependsOn: [sessionPool]
  params: {
    sessionPoolName: 'sessionpool${resourceToken}'
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    userPrincipalId: deployer().objectId
  }
}

// Pass endpoint to the function app
module api './app/api.bicep' = {
  params: {
    appSettings: {
      ACA_SESSION_POOL_ENDPOINT: sessionPool.outputs.poolManagementEndpoint
      // ... other settings
    }
  }
}
```

## Location Considerations

Session pools are available in a limited set of regions. Common choices:
- `eastus2`
- `westus2`
- `swedencentral`
- `australiaeast`

The session pool does NOT need to be in the same region as the function app, but keeping them
close reduces latency.
