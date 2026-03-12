---
name: azure-connectors
description: >
  Work with Azure managed API connectors (Office 365 and Microsoft Teams) to send emails,
  read emails, post Teams messages, reply to Teams threads, and list Teams channels. Also
  helps create and authenticate new connector resources in Azure. Remembers selected
  connectors in a `.env.connectors` file so you only configure once per repo. USE THIS
  SKILL whenever the user wants to interact with Office 365 email or Microsoft Teams
  channels through Azure, wants to set up an API connection in Azure, or mentions
  sending/reading emails or posting Teams messages via connectors. Covers: creating
  connections, authenticating via OAuth, persisting connector selections, listing teams
  and channels, posting and replying to messages, sending and reading emails.
---

# Azure Connectors

This skill helps you work with Azure managed API connectors — specifically Office 365
(email) and Microsoft Teams (channel messages). It uses `az cli` to make API calls
directly, with no Python or SDK dependencies.

## How Azure Managed Connectors Work

Azure managed connectors are pre-built API integrations hosted by Azure. Each connector
(Office 365, Teams, Salesforce, SharePoint, etc.) is an Azure resource that stores OAuth
credentials and proxies API calls through Azure Resource Manager (ARM).

The flow is:
1. **Create** a connection resource in your Azure subscription
2. **Authenticate** it via the Azure Portal (opens in browser)
3. **Call actions** through ARM's `dynamicInvoke` endpoint — your request is wrapped and
   forwarded to the connector's backend

All API calls go through ARM, so you authenticate with your Azure identity (via `az cli`),
and the connector handles the downstream OAuth token to the actual service (Office 365,
Teams, etc.).

## Prerequisites

- `az` CLI installed and logged in (`az login`)
- An Azure subscription with a resource group for connections

## Connector Persistence (`.env.connectors`)

To avoid asking the user for subscription, resource group, and connection details every time,
this skill uses a `.env.connectors` file in the repo root to remember which connectors have
been set up.

**Always check for `.env.connectors` at the start of any connector operation.** If the file
exists and has the needed connector, use those values directly — don't re-ask the user.

### File format

```bash
# Each value is the full ARM resource ID of the most recently used connector of that type
SELECTED_OFFICE365_CONNECTOR=/subscriptions/abc-123-def-456/resourceGroups/my-connectors-rg/providers/Microsoft.Web/connections/office365
SELECTED_TEAMS_CONNECTOR=/subscriptions/abc-123-def-456/resourceGroups/my-connectors-rg/providers/Microsoft.Web/connections/teams
```

The variable names follow the pattern `SELECTED_{CONNECTOR_UPPER}_CONNECTOR` where
`{CONNECTOR_UPPER}` is the connector type in uppercase (e.g., `OFFICE365`, `TEAMS`).
The value is always the full resource ID — this means you can use it directly as `CONN_ID`
for API calls without needing to reconstruct the path.

### When to write to `.env.connectors`

- **After creating a new connection**: save the full resource ID
- **When the user provides connection details manually**: build the resource ID and save it
- **When listing existing connections and the user picks one**: save its resource ID

### When to read from `.env.connectors`

- **Before any connector operation**: check if the file exists and has the needed connector.
  If it does, use the saved resource ID directly as `CONN_ID` — don't ask the user for
  subscription, resource group, or connection name. Confirm briefly: "Using your saved
  Office 365 connector (`$SELECTED_OFFICE365_CONNECTOR`)" so the user knows what's happening.

### Loading the file

```bash
if [ -f .env.connectors ]; then
  source .env.connectors
fi
```

For example, if the user wants to send an email and `SELECTED_OFFICE365_CONNECTOR` is set,
you can jump straight to making the API call with `CONN_ID="$SELECTED_OFFICE365_CONNECTOR"`.
If the needed variable is missing, fall back to asking the user.

### Saving to the file

When saving, append or update entries. Use this approach:

```bash
# Helper: set a key in .env.connectors (creates file if needed)
set_connector_env() {
  local key="$1" value="$2" file=".env.connectors"
  if [ -f "$file" ] && grep -q "^${key}=" "$file"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"  # macOS sed
  else
    echo "${key}=${value}" >> "$file"
  fi
}

# Example: after creating an office365 connection
CONN_RESOURCE_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME"
set_connector_env SELECTED_OFFICE365_CONNECTOR "$CONN_RESOURCE_ID"
```

### Ensuring `.gitignore` includes `.env.connectors`

After writing to `.env.connectors`, check if it's already in `.gitignore`. If not, add it:

```bash
if [ -f .gitignore ]; then
  grep -qxF '.env.connectors' .gitignore || echo '.env.connectors' >> .gitignore
else
  echo '.env.connectors' > .gitignore
fi
```

This prevents connector details (subscription IDs, resource groups) from being committed.

## Interactive Connector Discovery

When you have access to an interactive prompt tool (e.g., `askQuestion`, `ask_user`,
`vscode_askQuestions`, or similar), use it to guide the user through selecting their
Azure context instead of making them type out subscription IDs and resource group names.
This makes the experience much smoother — the user picks from a list rather than
copy-pasting GUIDs.

### When to use interactive discovery

Use this flow when **all** of these are true:
- No saved connector in `.env.connectors` for the needed type
- The user hasn't provided explicit connection details in their message
- You have access to an interactive prompt tool

If the user already gave you the details ("my sub is abc-123, resource group is my-rg"),
skip discovery and use what they gave you.

### Step 1: Select a subscription

List the user's Azure subscriptions and let them pick:

```bash
az account list --query '[].{name:name, id:id, isDefault:isDefault}' -o json
```

Present the results and ask which subscription to use. If there's only one, use it
automatically and confirm.

### Step 2: Find existing connectors (or pick a resource group to create one)

Check if connectors of the needed type already exist in the subscription:

```bash
SUB_ID="selected-subscription-id"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.Web/connections?api-version=2016-06-01" \
  | jq '[.value[] | select(.properties.api.name == "office365" or .properties.api.name == "teams") | {name: .name, type: .properties.api.name, resourceGroup: .id | split("/")[4], status: .properties.overallStatus, id: .id}]'
```

If connectors are found, present them and ask the user to pick one. Include the
connection status so they can see which ones are authenticated. **Always include
a "Create a new connector" option at the end of the list** — even if existing
connectors are found, the user may want a fresh one.

If no connectors exist, list resource groups and ask where to create it:

```bash
az group list --query '[].{name:name, location:location}' -o json
```

### Step 3: Save the selection

After the user picks (or creates) a connector, save it to `.env.connectors` as usual.
This way they only go through the interactive flow once per connector type.

### Example interaction flow

The conversation might look like:

> **User:** "Send an email to alice@contoso.com"
>
> **Agent:** No saved Office 365 connector found. Let me help you pick one.
>
> *(lists subscriptions via prompt tool)*
>
> **User picks:** "My Company Subscription (abc-123)"
>
> *(searches for existing office365 connectors in that subscription)*
>
> **Agent:** Found 2 Office 365 connectors:
> 1. `office365` in `prod-connectors` (Connected)
> 2. `office365-dev` in `dev-rg` (Connected)
> 3. Create a new connector
>
> **User picks:** #1
>
> *(saves to .env.connectors, then sends the email)*

### Falling back gracefully

If you don't have an interactive prompt tool, fall back to the non-interactive approach:
ask in the chat message for the subscription ID, resource group, and connection name,
or try `az account show` for the current subscription and search from there.

## Setting Up

### Get your Azure context

First, check if `.env.connectors` has a saved connector for the type you need:

```bash
if [ -f .env.connectors ]; then
  source .env.connectors
fi

# If the connector is already saved, you can use it directly:
# CONN_ID="$SELECTED_OFFICE365_CONNECTOR"  # or $SELECTED_TEAMS_CONNECTOR

# Otherwise, gather Azure context from az cli / the user
SUB_ID=$(az account show --query id -o tsv)
RG="your-resource-group"
LOCATION="westus"
```

### Create a connection

Replace `{CONNECTOR}` with `office365` or `teams`:

```bash
CONNECTOR="office365"   # or "teams"
CONN_NAME="$CONNECTOR"  # name for the connection resource

az rest --method PUT \
  --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME?api-version=2016-06-01" \
  --body "{
    \"location\": \"$LOCATION\",
    \"properties\": {
      \"api\": {
        \"id\": \"/subscriptions/$SUB_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/$CONNECTOR\"
      },
      \"displayName\": \"$CONNECTOR\",
      \"parameterValues\": {}
    }
  }"
```

### Authenticate the connection

After creating, open the Azure Portal to authenticate. The portal's connection edit page
is the only reliable way to complete the OAuth flow — do NOT use the `listConsentLinks`
or `confirmConsentCode` APIs, as they are fragile and often fail silently.

```bash
# Open the connection in Azure Portal to authenticate
PORTAL_URL="https://portal.azure.com/?feature.customportal=false#@your-tenant.onmicrosoft.com/resource/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME/edit"

echo "Open this URL to authenticate: $PORTAL_URL"
open "$PORTAL_URL"  # macOS — use xdg-open on Linux
```

In the portal, click **Authorize** and sign in with the account you want the connection to use.
Click **Save** after authorizing.

### Save the connection

After creating and authenticating, save the connection details so you don't have to ask
for them again:

```bash
set_connector_env() {
  local key="$1" value="$2" file=".env.connectors"
  if [ -f "$file" ] && grep -q "^${key}=" "$file"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

CONN_RESOURCE_ID="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME"
CONNECTOR_UPPER=$(echo "$CONNECTOR" | tr '[:lower:]' '[:upper:]')
set_connector_env "SELECTED_${CONNECTOR_UPPER}_CONNECTOR" "$CONN_RESOURCE_ID"

# Ensure .env.connectors is gitignored
if [ -f .gitignore ]; then
  grep -qxF '.env.connectors' .gitignore || echo '.env.connectors' >> .gitignore
else
  echo '.env.connectors' > .gitignore
fi
```

### Verify the connection

```bash
# Check connection status
az rest --method GET \
  --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME?api-version=2016-06-01" \
  --query 'properties.overallStatus' -o tsv
# Should print: Connected
```

## Making API Calls

All connector actions use the `dynamicInvoke` endpoint. The pattern is always:

```bash
# Use saved connector if available, otherwise construct from parts
CONN_ID="${SELECTED_OFFICE365_CONNECTOR:-/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/connections/$CONN_NAME}"

az rest --method POST \
  --url "https://management.azure.com${CONN_ID}/dynamicInvoke?api-version=2016-06-01" \
  --body '{
    "request": {
      "method": "GET",
      "path": "/api/path/here",
      "queries": {},
      "body": {}
    }
  }'
```

The response is always wrapped: `{"response": {"statusCode": "OK", "body": {...}}}`.
Use `--query 'response.body'` to extract the actual data.

`az rest` handles authentication automatically — no need to manage tokens manually.

For the detailed API paths for each connector, see the reference files:
- `references/teams-api.md` — Teams channel messages, replies, teams, channels
- `references/office365-api.md` — Email send, read, reply, manage

## Quick Reference

### Common variables

```bash
# Load saved connector resource IDs if available
if [ -f .env.connectors ]; then source .env.connectors; fi

# Use the saved resource ID directly as CONN_ID
CONN_ID="$SELECTED_OFFICE365_CONNECTOR"  # or $SELECTED_TEAMS_CONNECTOR
```
