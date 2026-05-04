# Troubleshooting Reference

This reference covers common issues, diagnostic approaches, and fixes for
azure-functions-agents apps — both local and deployed.

## General Approach

1. **Read the error.** Don't guess. Check terminal output (local) or Application Insights (deployed).
2. **Check startup warnings.** The framework logs `WARNING` for every agent it skips and every
   capability it can't load. These appear at startup in `func start` output.
3. **Test incrementally.** Strip down to the simplest agent, confirm it works, then add complexity.
4. **Check env vars.** Many failures are caused by missing or misconfigured environment variables.
   The framework leaves unresolved `$VAR` references unchanged (no error, just wrong values).

## Local Development Issues

### `func start` fails to start

**ModuleNotFoundError or ImportError:**
- Virtual environment not activated — run `source .venv/bin/activate`
- Dependencies not installed — run `pip install -r requirements.txt`
- Wrong Python version — requires Python 3.12+. Check `python --version`

**"No job functions found":**
- `function_app.py` is missing or not in the right directory
- The `app` variable isn't at module level
- `host.json` is missing the extension bundle

**Port 7071 already in use:**
- Another `func start` or process is using the port
- Kill it: `lsof -ti:7071 | xargs kill -9`

### Azurite issues

**"Value for one of the query parameters specified in the request URI is invalid":**
- Run Azurite with `--skipApiVersionCheck`

**Timer/queue triggers not firing locally:**
- Azurite must be running. Non-HTTP triggers require storage.
- Check that `AzureWebJobsStorage` is `UseDevelopmentStorage=true` in `local.settings.json`

### Agent not registered at startup

If you see `Skipping '<name>': ...` in the startup logs:

- **"missing or invalid 'trigger' section (must have 'type')"** — the `.agent.md` file is
  missing the `trigger:` block or `type:` field in frontmatter
- **"unknown trigger type"** — the trigger type name is wrong. Check [triggers reference](./triggers.md)
- **"azure-functions-connectors package not installed"** — this error is from an older
  version of the package. Update to the latest `azurefunctions-agents-runtime` which includes
  connector tool support by default.

### GitHub authentication failures

**Agent returns no response or errors about authentication:**
- Check if `GITHUB_TOKEN` is set in `local.settings.json`
- If using Copilot CLI: verify `copilot auth show-token` works
- If using PAT: ensure it has **Copilot requests → Read-only** permission
- Token may be expired — regenerate at [github.com/settings/tokens](https://github.com/settings/tokens?type=beta)

### Sandbox / execute_python not available

**"execution_sandbox: missing 'session_pool_management_endpoint', skipping":**
- The `execution_sandbox` block in the agent's YAML frontmatter is missing the endpoint

**"execution_sandbox: could not resolve endpoint":**
- The `$ACA_SESSION_POOL_ENDPOINT` env var is not set in `local.settings.json`
- Set it to a valid session pool management endpoint URL

**403 from session pool:**
- Your local identity doesn't have the **Azure ContainerApps Session Executor** role
- Assign it:
  ```bash
  USER_OID=$(az ad signed-in-user show --query id -o tsv)
  az role assignment create \
    --assignee "$USER_OID" \
    --role "Azure ContainerApps Session Executor" \
    --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/sessionPools/{pool}"
  ```

### Connector tools not working

**No connector tools appear in agent:**
- Check that `tools_from_connections` is in the agent's YAML frontmatter
- Check that the `connection_id` env var is set and resolves to a valid resource ID
- Check that `azurefunctions-agents-runtime` is up to date

**401/403 when calling connector actions:**
- **V1**: Your identity needs **Contributor** role on the connection resource
- **V2**: Your identity also needs to be in the connector gateway's ACL
- The connection may not be authenticated — authorize it in Azure Portal
  (API Connection → Edit API connection → Authorize → Save)

**"Error (404)" or "Error (400)" from connector:**
- The operation may require parameters you didn't provide
- Check the tool's parameter schema — the agent might be calling it incorrectly
- Look at the full error response in logs for details

## Deployed App Issues

### Checking Application Insights

Application Insights is the primary diagnostic tool for deployed apps.

**In Azure Portal:**
1. Go to the resource group (named `rg-<azd-env-name>`)
2. Open the **Application Insights** resource
3. Use these views:
   - **Transaction search** — find specific requests, see traces and exceptions
   - **Failures** — overview of failed requests and exceptions
   - **Logs** — run KQL queries against telemetry

**Useful KQL queries:**

```kql
// Recent exceptions
exceptions
| where timestamp > ago(1h)
| order by timestamp desc
| project timestamp, problemId, outerMessage, details

// Agent function invocations
requests
| where timestamp > ago(1h)
| where name contains "agent"
| order by timestamp desc
| project timestamp, name, resultCode, duration, success

// All traces from a specific function invocation
// (get the operation_id from a request row first)
union requests, traces, exceptions
| where operation_Id == "<operation-id>"
| order by timestamp asc
| project timestamp, itemType, message, outerMessage

// Warning and error logs
traces
| where timestamp > ago(1h)
| where severityLevel >= 2
| order by timestamp desc
| project timestamp, message, severityLevel
```

**Via Azure CLI:**
```bash
# Check function app status
az functionapp show -g <rg> -n <func-app> --query "state" -o tsv

# Check app settings (verify env vars are set)
az functionapp config appsettings list -g <rg> -n <func-app> --query "[].{name:name}" -o table

# View recent logs (live tail)
az webapp log tail -g <rg> -n <func-app>
```

### Function app not starting

- Check that all required app settings are configured (especially `GITHUB_TOKEN`)
- Verify the managed identity has proper RBAC (storage, session pool, connectors)
- Check Application Insights for startup exceptions

### Timer not firing in production

- Verify the NCRONTAB schedule is correct (6-part with seconds, or 5-part auto-prepended)
- Check if the function is listed: `az functionapp function list -g <rg> -n <func-app>`
- Test manually:
  ```bash
  MASTER_KEY=$(az functionapp keys list -g <rg> -n <func-app> --query "masterKey" -o tsv)
  curl -X POST "https://<func-app>.azurewebsites.net/admin/functions/<agent_name>_agent" \
    -H "x-functions-key: $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d '{}'
  ```

### RBAC / permission issues

Common role assignments needed:

| Resource | Role | Who | Why |
|---|---|---|---|
| Storage Account | Storage Blob Data Owner | Managed Identity | Function app storage |
| Storage Account | Storage Queue Data Contributor | Managed Identity | Queue triggers |
| Storage Account | Storage Table Data Contributor | Managed Identity | Table storage |
| App Insights | Monitoring Metrics Publisher | Managed Identity | Telemetry |
| Session Pool | Azure ContainerApps Session Executor | Managed Identity + User | Code execution |
| API Connection | Contributor | Managed Identity + User | Connector invocation |
| Subscription | Reader | Managed Identity | ARM REST API (if using azure_rest tool) |

If RBAC is missing, the Bicep templates handle most of it — but if deploying manually or
reusing existing resources, check each role assignment.

```bash
# Check role assignments on a resource
az role assignment list --scope "<resource-id>" -o table
```

### Connector auth expired or not set up

After `azd up`, API Connections are created but **not authenticated**. You must authorize
them manually in the Azure Portal. If a connector stops working after some time, the OAuth
token may have expired — re-authorize it.

## Common Error Messages

| Error | Meaning | Fix |
|---|---|---|
| "Skipping '...': missing or invalid 'trigger' section" | Agent file frontmatter malformed | Add `trigger:` with `type:` field |
| "azure-functions-connectors package not installed" | Outdated package version | `pip install --upgrade azurefunctions-agents-runtime` |
| "execution_sandbox: missing 'session_pool_management_endpoint'" | No endpoint configured | Add `execution_sandbox:` to frontmatter |
| "execution_sandbox: could not resolve endpoint" | Env var not set | Set `ACA_SESSION_POOL_ENDPOINT` |
| "Failed to resume session" | Session state corrupted or expired | Start a new session (omit session ID) |
| "Agent returned invalid JSON" | HTTP agent's response didn't match expected format | Improve agent instructions or `response_example` |
| "Error (401/403)" from connector | Auth or RBAC issue | Authorize connector; check role assignments |
| "ACA sessions API error" | Session pool access denied or pool misconfigured | Check Session Executor role assignment |
| Tool calls return unhelpful results | Agent instructions too vague | Make instructions more specific; add examples |

## Iterative Improvement

Agent behavior depends heavily on the markdown instructions. If the agent isn't doing what
you want:

1. **Be more specific in instructions.** Instead of "gather news", say "use execute_python
   to fetch RSS feeds from https://... and parse the XML response."
2. **Add step-by-step procedures.** Numbered steps work better than prose.
3. **Show examples.** If the agent should produce specific output, include an example in
   the instructions.
4. **Check tool availability.** The agent can only use tools that are configured. If it's
   trying to do something without the right tool, add the tool or connector.
5. **Review agent logs.** When `logger: true` (default), the agent's full response including
   tool calls is logged. Review these to understand what the agent did and where it went wrong.
6. **Test locally first.** Use `func start` and the chat UI to iterate quickly before deploying.
   For timer agents, use `POST http://localhost:7071/admin/functions/<function_name>` to trigger
   manually.
