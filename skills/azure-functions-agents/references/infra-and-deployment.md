# Infrastructure and Deployment Reference

Deploy azure-functions-agents apps to Azure using Bicep templates and the Azure Developer CLI (`azd`).

## Bicep Template Files

Start from the template files in [assets/infra/](../assets/infra/). Copy the entire directory
to the project's `infra/` folder, then **modify `main.bicep`** to match the app's needs:

- Add session pool modules only if the agent uses `execution_sandbox`
- Add connector modules only if the agent uses `tools_from_connections` — an app may need
  zero connectors, one, or several depending on what services the agent interacts with
- The `office365-connection.bicep` template is just an example — adapt it for any managed API
  connector (Teams, SharePoint, SQL, etc.) by changing the `managedApis` name
- Add Bicep `param` declarations and wire them into `appSettings` for any app-specific env vars
- Add corresponding entries to `main.parameters.json` so `azd` maps env vars to Bicep params
- Copy [abbreviations.json](../assets/infra/../references/abbreviations.json) into `infra/`

**Do not use the templates as-is with comments.** Produce a clean `main.bicep` tailored to
the app — uncommented blocks for the features needed, no commented blocks for features not needed.

### Template files

| File | Purpose | Always needed? |
|---|---|---|
| [main.bicep](../assets/infra/main.bicep) | Root template — resource group, identity, plan, storage, monitoring | Yes |
| [main.parameters.json](../assets/infra/main.parameters.json) | Maps azd env vars to Bicep params | Yes |
| [app/api.bicep](../assets/infra/app/api.bicep) | Function App (Flex Consumption) + Azure Files mount | Yes |
| [app/rbac.bicep](../assets/infra/app/rbac.bicep) | Storage + App Insights RBAC | Yes |
| [app/session-pool.bicep](../assets/infra/app/session-pool.bicep) | ACA Dynamic Sessions pool | If using `execution_sandbox` |
| [app/session-pool-rbac.bicep](../assets/infra/app/session-pool-rbac.bicep) | Session Executor role for managed identity + deployer | If using `execution_sandbox` |
| [app/office365-connection.bicep](../assets/infra/app/office365-connection.bicep) | Office 365 API Connection | If using Office 365 connector |
| [app/connector-rbac.bicep](../assets/infra/app/connector-rbac.bicep) | Contributor role on connection for managed identity | If using connectors |

### Adapting main.bicep

The template `main.bicep` has commented-out blocks for session pools and connectors. When
producing the app's `main.bicep`, **only include modules the app actually needs** and remove
all commented-out blocks. For example, an app that needs a session pool + Office 365
connector should produce a `main.bicep` that:

1. Adds `param toEmail string` (or whatever app-specific params are needed)
2. Adds `var connectionName = 'office365-${resourceToken}'`
3. Includes the session pool + RBAC modules (uncommented)
4. Includes the connector + RBAC modules (uncommented)
5. Wires outputs into `api` module's `appSettings`:
   ```bicep
   appSettings: {
     // ... base settings ...
     ACA_SESSION_POOL_ENDPOINT: sessionPool.outputs.poolManagementEndpoint
     O365_CONNECTION_ID: office365Connection.outputs.connectionId
     TO_EMAIL: toEmail
   }
   ```
6. Adds Bicep outputs for connection name etc.
7. Adds matching entries to `main.parameters.json`

### Creating connector Bicep for other connector types

The `office365-connection.bicep` template can be adapted for any managed API connector.
Change the `managedApis` name to match the connector type:

| Connector | API name |
|---|---|
| Office 365 Outlook | `office365` |
| Microsoft Teams | `teams` |
| SharePoint | `sharepointonline` |
| SQL Server | `sql` |
| Outlook.com | `outlook` |

## azure.yaml

```yaml
name: my-agent-app
services:
  api:
    project: ./src
    language: python
    host: function
```

## Deployment Workflow

### First-time deployment

```bash
cd <project-root>

# Initialize azd
azd init

# Set required environment variables
azd env set GITHUB_TOKEN "<your-github-pat>"
azd env set COPILOT_MODEL "claude-opus-4.6"    # optional, defaults in Bicep

# Set app-specific variables
azd env set TO_EMAIL "user@example.com"         # if applicable

# Deploy everything (provision infrastructure + deploy code)
azd up
```

### Provision-first workflow (recommended for local dev)

If the app uses sandbox or connectors, provision infrastructure first so you can develop
locally against real Azure resources:

```bash
azd init
azd env set GITHUB_TOKEN "<your-github-pat>"
# Set other env vars as needed
azd provision    # creates Azure resources WITHOUT deploying code
```

Then populate `local.settings.json` from the provisioned values — see
"Populating local.settings.json from provisioned resources" below.

After local development, deploy code:
```bash
azd deploy
```

### Subsequent deployments

```bash
azd deploy       # code changes only
azd provision    # infrastructure changes only
azd up           # full redeploy (provision + deploy)
```

### GitHub PAT for Deployment

A GitHub PAT is **always required** when deployed to Azure — no alternative auth exists for cloud.

Create a fine-grained PAT:
1. Go to [github.com/settings/tokens](https://github.com/settings/tokens?type=beta)
2. Click **Generate new token** (fine-grained)
3. Name: `azure-functions-agent-runtime`
4. Under **Permissions** → **Copilot requests** → **Read-only**
5. Generate and copy the token
6. Set via `azd env set GITHUB_TOKEN "<token>"`

## Populating local.settings.json from provisioned resources

After `azd provision`, extract resource values for local development:

```bash
# Get azd outputs
azd env get-values
```

This shows key-value pairs like `AZURE_FUNCTION_NAME`, `O365_CONNECTION_NAME`, etc.
But `local.settings.json` often needs full resource IDs, not just names. Use these commands:

### Session pool endpoint

```bash
# If the session pool was created by azd:
RG="rg-$(azd env get-value AZURE_ENV_NAME)"
POOL_NAME=$(az containerapp sessionpool list -g "$RG" --query "[0].name" -o tsv)
POOL_ENDPOINT=$(az containerapp sessionpool show -g "$RG" -n "$POOL_NAME" \
  --query "properties.poolManagementEndpoint" -o tsv)

echo "ACA_SESSION_POOL_ENDPOINT=$POOL_ENDPOINT"
# → Add to local.settings.json Values
```

### Connector connection ID

```bash
# Get the full resource ID for the connection
RG="rg-$(azd env get-value AZURE_ENV_NAME)"
CONN_NAME=$(azd env get-value O365_CONNECTION_NAME)
CONN_ID=$(az rest --method GET \
  --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME?api-version=2016-06-01" \
  --query "id" -o tsv)

echo "O365_CONNECTION_ID=$CONN_ID"
# → Add to local.settings.json Values
```

### Checking and authenticating connectors

After provisioning, connectors are created but **not authenticated**. Check the status
and get the auth link:

```bash
# Check connection status
az rest --method GET \
  --url "https://management.azure.com${CONN_ID}?api-version=2016-06-01" \
  --query "properties.overallStatus" -o tsv
# "Connected" = authenticated, "Error" or "Unauthenticated" = needs auth
```

To authenticate, open the connection in the Azure Portal:

```bash
SUB_ID=$(az account show --query id -o tsv)
PORTAL_URL="https://portal.azure.com/#@/resource/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME/edit"

echo "Open this URL to authenticate: $PORTAL_URL"
open "$PORTAL_URL"   # macOS
```

In the portal: click **Authorize** → sign in → click **Save**.

**This must be done both after initial provisioning (for local dev) and after full
deployment.** If the connector stops working later, the OAuth token may have expired —
re-authorize it the same way.

### Assigning local user RBAC for connectors

Your local identity (from `az login`) needs **Contributor** on the connection to invoke it locally:

```bash
USER_OID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --assignee "$USER_OID" \
  --role "Contributor" \
  --scope "$CONN_ID"
```

## Testing Timer Triggers (deployed)

```bash
# Get the master key
MASTER_KEY=$(az functionapp keys list -g <rg> -n <func-app> --query "masterKey" -o tsv)

# Trigger the function manually
curl -X POST "https://<func-app>.azurewebsites.net/admin/functions/<agent_name>_agent" \
  -H "x-functions-key: $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'
```

## abbreviations.json

Use the standard abbreviations file at [references/abbreviations.json](./abbreviations.json).
Copy it to `infra/abbreviations.json` in the project.

Key abbreviations used:
- `webSitesFunctions`: `func-`
- `webServerFarms`: `plan-`
- `storageStorageAccounts`: `st`
- `managedIdentityUserAssignedIdentities`: `id-`
- `resourcesResourceGroups`: `rg-`
- `operationalInsightsWorkspaces`: `log-`
- `insightsComponents`: `appi-`
