# Teams Connector API Reference

All calls use `dynamicInvoke` via `az rest`. Set up your variables first:

```bash
# Load from .env.connectors or construct manually
if [ -f .env.connectors ]; then source .env.connectors; fi
CONN_ID="$SELECTED_TEAMS_CONNECTOR"
```

Helper function for making calls:

```bash
connector_call() {
  local method="$1" path="$2" body="$3"
  local req='{"request":{"method":"'$method'","path":"'$path'","queries":{}}}'
  if [ -n "$body" ]; then
    req='{"request":{"method":"'$method'","path":"'$path'","queries":{},"body":'$body'}}'
  fi
  az rest --method POST \
    --url "https://management.azure.com${CONN_ID}/dynamicInvoke?api-version=2016-06-01" \
    --body "$req" \
    --query 'response.body'
}
```

---

## Finding Teams and Channels

Before you can post or read messages, you need the team ID and channel ID.

### List your teams

```bash
connector_call GET "/beta/me/joinedTeams"
```

Response contains `value` array. Each team has `id` and `displayName`:
```json
{"value": [{"id": "f9beb78b-...", "displayName": "My Team", ...}]}
```

### List channels in a team

```bash
TEAM_ID="your-team-id"
connector_call GET "/beta/groups/$TEAM_ID/channels"
```

Each channel has `id` and `displayName`. The General channel is always present.
Channel IDs look like `19:abc123...@thread.tacv2`.

### Get a specific channel

```bash
connector_call GET "/beta/teams/$TEAM_ID/channels/$CHANNEL_ID"
```

---

## Reading Messages

### Get recent messages from a channel

```bash
connector_call GET "/beta/teams/$TEAM_ID/channels/$CHANNEL_ID/messages"
```

Returns top-level posts (not replies). Messages come back newest-first.
Each message has:
- `id` — message ID (needed for replies)
- `body.content` — the message HTML content
- `from.user.displayName` — who sent it
- `createdDateTime` — when it was sent
- `messageType` — "message" for regular posts, "systemEventMessage" for system events

### Get replies to a message

```bash
MSG_ID="message-id-here"
connector_call GET "/v1.0/teams/$TEAM_ID/channels/$CHANNEL_ID/messages/$MSG_ID/replies"
```

Returns replies in the thread, newest-first.

---

## Posting Messages

### Post a new message to a channel

```bash
connector_call POST "/v3/beta/teams/$TEAM_ID/channels/$CHANNEL_ID/messages" \
  '{"body":{"content":"Hello from the connector!","contentType":"html"}}'
```

The response includes the new message's `id` (useful for replying).

### Reply to a message

```bash
MSG_ID="message-id-to-reply-to"
connector_call POST "/v2/beta/teams/$TEAM_ID/channels/$CHANNEL_ID/messages/$MSG_ID/replies" \
  '{"body":{"content":"This is a reply!","contentType":"html"}}'
```

### Post with HTML formatting

The `contentType` is `html`, so you can use basic HTML:

```bash
connector_call POST "/v3/beta/teams/$TEAM_ID/channels/$CHANNEL_ID/messages" \
  '{"body":{"content":"<b>Bold</b> and <i>italic</i> and <a href=\"https://example.com\">links</a>","contentType":"html"}}'
```

---

## Other Operations

### Create a channel

```bash
connector_call POST "/beta/groups/$TEAM_ID/channels" \
  '{"displayName":"New Channel","description":"Channel description"}'
```

### Get team details

```bash
connector_call GET "/beta/teams/$TEAM_ID"
```
