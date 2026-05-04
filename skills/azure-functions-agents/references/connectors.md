# Connectors Reference

Azure API Connections provide pre-built integrations with 1,400+ SaaS services (Office 365,
Teams, SQL, Salesforce, SAP, etc.). When referenced in an agent's `tools_from_connections`,
the framework dynamically discovers all available actions and exposes them as tools.

## V1 vs V2 Connectors

The framework supports both connector versions, auto-detected via connection ID format.

| Version | ID contains | Invocation method | Status |
|---|---|---|---|
| **V1** | `/connections/` | ARM `dynamicInvoke` | Fully available |
| **V2** | `/aigateways/` or `/connectorgateways/` | Direct HTTP data plane | Requires allowlisting (not fully live yet) |

### When to use which

- **Try V2 first** (`connectorgateway`) — lower latency, direct data plane calls
- **Fall back to V1** if V2 creation fails (user may not be allowlisted for the service)
- V1 connections work for everyone and are the reliable fallback

### Connection ID formats

```
# V1 (standard API Connection)
/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connections/{name}

# V2 (connector gateway)
/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connectorGateways/{gateway}/connections/{name}
```

## Creating Connectors

### V2 Connector (connectorgateway) — Try First

Use `az rest` to create a V2 connector via the connector gateway. The `connectorGateways`
resource type requires API version **`2026-05-01-preview`** — older API versions return
`NoRegisteredProviderFound`.

```bash
# Create a connector gateway (if one doesn't exist)
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connectorGateways/{gateway-name}?api-version=2026-05-01-preview" \
  --body '{
    "location": "{location}",
    "identity": { "type": "SystemAssigned" },
    "properties": {}
  }'

# Create a connection on the gateway
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connectorGateways/{gateway-name}/connections/{connection-name}?api-version=2026-05-01-preview" \
  --body '{
    "properties": {
      "connectorName": "office365",
      "displayName": "Office 365 Outlook Connection"
    }
  }'
```

#### Listing V2 connections

V2 connections do **not** appear under `Microsoft.Web/connections` (that's V1 only). They
are nested children of a `connectorGateways` resource and must be enumerated per gateway:

```bash
# 1. Find all connector gateways in a subscription
az resource list --subscription {sub} \
  --resource-type Microsoft.Web/connectorGateways \
  --query '[].id' -o tsv

# 2. For each gateway, list its connections
az rest --method GET \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connectorGateways/{gateway-name}/connections?api-version=2026-05-01-preview"
```

Each connection's properties include `connectorName` (e.g. `office365`, `kusto`, `sql`),
`overallStatus` (`Connected` / `Error`), `displayName`, and `connectionRuntimeUrl`.

If this fails with an error about the resource provider not being registered or the user not
being allowlisted, fall back to V1.

### V1 Connector (standard API Connection) — Fallback

V1 connectors can be created via Bicep (recommended for infra-as-code) or Azure CLI.

**Via Bicep** (add to `infra/app/`):

```bicep
// office365-connection.bicep
param connectionName string
param location string = resourceGroup().location
param tags object = {}

resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: connectionName
  location: location
  tags: tags
  properties: {
    displayName: 'Office 365 Outlook'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
  }
}

output connectionId string = office365Connection.id
output connectionName string = office365Connection.name
```

**Via Azure CLI:**

```bash
az resource create \
  --resource-group {rg} \
  --resource-type "Microsoft.Web/connections" \
  --name {connection-name} \
  --location {location} \
  --properties '{
    "displayName": "Office 365 Outlook",
    "api": {
      "id": "/subscriptions/{sub}/providers/Microsoft.Web/locations/{location}/managedApis/office365"
    }
  }'
```

### Common Managed API names

| Service | API name |
|---|---|
| Office 365 Outlook | `office365` |
| Microsoft Teams | `teams` |
| SharePoint | `sharepointonline` |
| SQL Server | `sql` |
| Salesforce | `salesforce` |
| Outlook.com | `outlook` |

Find the full list: `az rest --method GET --url "https://management.azure.com/subscriptions/{sub}/providers/Microsoft.Web/locations/{location}/managedApis?api-version=2016-06-01"`

## Authenticating Connectors

After creating a connection, it must be authenticated (authorized with OAuth).

### Check connection status

```bash
# Using the full connection resource ID
az rest --method GET \
  --url "https://management.azure.com{connection-resource-id}?api-version=2016-06-01" \
  --query "properties.overallStatus" -o tsv
# Returns: "Connected" (authenticated) or "Error" / "Unauthenticated" (needs auth)
```

### Authenticate via Azure Portal

Open the connection's edit page directly:

```bash
SUB_ID=$(az account show --query id -o tsv)
PORTAL_URL="https://portal.azure.com/#@/resource/subscriptions/$SUB_ID/resourceGroups/{rg}/providers/Microsoft.Web/connections/{connection-name}/edit"

echo "Open this URL to authenticate the connector: $PORTAL_URL"
open "$PORTAL_URL"   # macOS
```

In the portal: click **Authorize** → sign in with the account the connector should use →
click **Save**.

### When to authenticate

- **After `azd provision`** — if developing locally against provisioned resources
- **After `azd up`** — if deploying for the first time
- **If connector stops working** — the OAuth token may have expired; re-authorize

### Verify authentication succeeded

```bash
az rest --method GET \
  --url "https://management.azure.com{connection-resource-id}?api-version=2016-06-01" \
  --query "properties.overallStatus" -o tsv
# Should now return "Connected"
```

## RBAC for Connectors

### V1 Connectors

The identity invoking the connector needs **Contributor** role on the connection resource.

**For managed identity (deployed app):**

```bicep
// connector-rbac.bicep
param connectionName string
param managedIdentityPrincipalId string

var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource connection 'Microsoft.Web/connections@2016-06-01' existing = {
  name: connectionName
}

resource connectorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(connection.id, managedIdentityPrincipalId, contributorRoleId)
  scope: connection
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
```

**For local development (your user identity):**

```bash
# Get your user object ID
USER_OID=$(az ad signed-in-user show --query id -o tsv)

# Assign Contributor on the connection
az role assignment create \
  --assignee "$USER_OID" \
  --role "Contributor" \
  --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connections/{connection-name}"
```

### V2 Connectors

V2 connectors need **both**:
1. **Contributor** role on the connection resource (same as V1)
2. **ACL entry** — the identity must be added to the connector gateway's access control list

```bash
# Add identity to ACL (V2 only)
az rest --method POST \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connectorGateways/{gateway}/connections/{connection}/addAccessPolicy?api-version=2026-05-01-preview" \
  --body '{
    "properties": {
      "objectId": "{principal-object-id}",
      "tenantId": "{tenant-id}"
    }
  }'
```

## Using Connectors in Agents

Add to the agent's YAML frontmatter:

```yaml
tools_from_connections:
  - connection_id: $O365_CONNECTION_ID      # env var pointing to the connection resource ID
    prefix: email                            # optional: customize tool name prefix
  - connection_id: $TEAMS_CONNECTION_ID
    prefix: teams
```

At runtime, the framework:
1. Resolves the env var to get the full connection resource ID
2. Calls ARM to load the connection's Swagger schema
3. Generates Copilot SDK Tool objects for each operation
4. Tool names follow the pattern: `{prefix}_{api_name}_{operation_id}` (max 64 chars)

The agent can then call any connector action as a tool (send email, post Teams message, query SQL, etc.) without any custom code.

## Connector Environment Variables

In `local.settings.json` (local) or Bicep app settings (deployed):

```json
{
  "O365_CONNECTION_ID": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connections/{name}"
}
```

For V2:
```json
{
  "O365_CONNECTION_ID": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/connectorGateways/{gateway}/connections/{name}"
}
```
