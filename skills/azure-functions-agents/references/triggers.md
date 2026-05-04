# Trigger Reference

All trigger types supported in `.agent.md` YAML frontmatter. The `type` field determines the
Azure Functions trigger binding; all other fields are passed as parameters.

> **Environment variable substitution**: All string values under `trigger.*` (except `type`)
> support `$VAR` or `%VAR%` syntax for full-string env var replacement.

The framework calls `getattr(app, trigger_type)(**params)` to register the function, so any
parameter accepted by the Azure Functions Python SDK decorator can be used.

---

## Timer trigger

Runs the agent on a cron schedule.

```yaml
trigger:
  type: timer_trigger
  schedule: "0 0 9 * * *"
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `schedule` | Yes | — | NCRONTAB expression. 6-part (with seconds) or 5-part (seconds auto-prepended as `0`) |
| `run_on_startup` | No | `false` | Run when the host starts |
| `use_monitor` | No | `true` | Monitor for missed executions |

**Schedule examples:**
- `"0 0 9 * * *"` — daily at 9:00 AM UTC
- `"0 */5 * * * *"` — every 5 minutes
- `"0 30 14 * * 1-5"` — weekdays at 2:30 PM UTC
- `"0 9 * * *"` — 5-part (seconds auto-prepended → `"0 0 9 * * *"`)

Ref: [Azure Functions timer trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-timer)

---

## HTTP trigger

Exposes the agent as a REST API endpoint with structured JSON responses.

```yaml
trigger:
  type: http_trigger
  route: my-endpoint
  methods: ["POST"]
  auth_level: FUNCTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `route` | Yes | — | URL path for the endpoint |
| `methods` | No | `["POST"]` | HTTP methods to accept |
| `auth_level` | No | `FUNCTION` | `ANONYMOUS`, `FUNCTION`, or `ADMIN` |

Use `response_example` (top-level, not under `trigger`) to define the expected JSON output:

```yaml
response_example: |
  {
    "summary": "Brief text",
    "keywords": ["a", "b"]
  }
```

If `response_example` is omitted, raw agent text is returned as `text/plain`.
`response_schema` (JSON Schema) is also supported for advanced use cases.

Ref: [Azure Functions HTTP trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-http-webhook)

---

## Queue trigger

Triggers on Azure Storage queue messages.

```yaml
trigger:
  type: queue_trigger
  queue_name: my-queue
  connection: $STORAGE_CONNECTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `queue_name` | Yes | — | Queue name |
| `connection` | Yes | — | App setting for storage connection string |

Ref: [Azure Functions queue trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-storage-queue-trigger)

---

## Blob trigger

Triggers on blob create/update in Azure Storage.

```yaml
trigger:
  type: blob_trigger
  path: my-container/{name}
  connection: $STORAGE_CONNECTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `path` | Yes | — | Blob path pattern (e.g., `container/{name}`) |
| `connection` | Yes | — | App setting for storage connection string |
| `source` | No | `LogsAndContainerScan` | `EventGrid` for lower latency |

Ref: [Azure Functions blob trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-storage-blob-trigger)

---

## Event Hub trigger

```yaml
trigger:
  type: event_hub_message_trigger
  event_hub_name: my-hub
  connection: $EVENTHUB_CONNECTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `event_hub_name` | Yes | — | Event Hub name |
| `connection` | Yes | — | App setting for Event Hub connection |
| `consumer_group` | No | `$Default` | Consumer group |
| `cardinality` | No | `ONE` | `ONE` or `MANY` |

Ref: [Azure Functions Event Hub trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-event-hubs-trigger)

---

## Service Bus queue trigger

```yaml
trigger:
  type: service_bus_queue_trigger
  queue_name: my-queue
  connection: $SERVICEBUS_CONNECTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `queue_name` | Yes | — | Service Bus queue name |
| `connection` | Yes | — | App setting for Service Bus connection |
| `is_sessions_enabled` | No | `false` | Session-aware processing |
| `cardinality` | No | `ONE` | `ONE` or `MANY` |
| `auto_complete_messages` | No | `true` | Auto-complete after processing |

---

## Service Bus topic trigger

```yaml
trigger:
  type: service_bus_topic_trigger
  topic_name: my-topic
  subscription_name: my-sub
  connection: $SERVICEBUS_CONNECTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `topic_name` | Yes | — | Topic name |
| `subscription_name` | Yes | — | Subscription name |
| `connection` | Yes | — | App setting for Service Bus connection |
| `is_sessions_enabled` | No | `false` | Session-aware processing |
| `cardinality` | No | `ONE` | `ONE` or `MANY` |

Ref: [Azure Functions Service Bus trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-service-bus-trigger)

---

## Cosmos DB trigger

```yaml
trigger:
  type: cosmos_db_trigger
  database_name: my-db
  container_name: my-container
  connection: $COSMOSDB_CONNECTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `database_name` | Yes | — | Database name |
| `container_name` | Yes | — | Container to monitor |
| `connection` | Yes | — | App setting for Cosmos DB connection |
| `lease_connection` | No | Same as `connection` | Connection for lease container |
| `lease_container_name` | No | `leases` | Lease container name |
| `create_lease_container_if_not_exists` | No | `false` | Auto-create lease container |
| `max_items_per_invocation` | No | — | Max documents per invocation |
| `start_from_beginning` | No | `false` | Start from beginning of change history |

Ref: [Azure Functions Cosmos DB trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-cosmosdb-v2-trigger)

---

## Event Grid trigger

```yaml
trigger:
  type: event_grid_trigger
```

No additional parameters — Event Grid subscriptions are configured externally.

Ref: [Azure Functions Event Grid trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-event-grid-trigger)

---

## Kafka trigger

```yaml
trigger:
  type: kafka_trigger
  topic: my-topic
  broker_list: $KAFKA_BROKERS
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `topic` | Yes | — | Kafka topic |
| `broker_list` | Yes | — | Comma-separated brokers |
| `consumer_group` | No | — | Consumer group |
| `cardinality` | No | `ONE` | `ONE` or `MANY` |
| `authentication_mode` | No | `Plain` | `Gssapi`, `Plain`, `ScramSha256`, `ScramSha512` |
| `protocol` | No | `plaintext` | Security protocol |

Ref: [Azure Functions Kafka trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-kafka-trigger)

---

## SQL trigger

```yaml
trigger:
  type: sql_trigger
  table_name: dbo.MyTable
  connection_string_setting: $SQL_CONNECTION
```

| Parameter | Required | Default | Description |
|---|---|---|---|
| `table_name` | Yes | — | SQL table to monitor |
| `connection_string_setting` | Yes | — | App setting for SQL connection string |

Ref: [Azure Functions SQL trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-azure-sql-trigger)

---

## Connector triggers

> **Note**: Connector triggers are no longer included in the `azurefunctions-agents-runtime`
> package. Connector **tools** (calling connector actions from agents) are still fully
> supported. If you need connector-based triggers, use a different trigger type (e.g., timer,
> HTTP) and have the agent call connector tools to poll for or react to events.

---

## Trigger Data

When a triggered agent runs, the prompt sent to the agent includes:

```
Triggered by: <trigger_type>

Trigger data:
```json
{ ... serialized binding data ... }
```​
```

This applies to all trigger types. Timer data includes `{"past_due": false, "isPastDue": false}`.
HTTP trigger data is the request body. Queue/blob/etc. data is the serialized message or event.
