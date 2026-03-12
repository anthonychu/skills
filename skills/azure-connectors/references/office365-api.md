# Office 365 Connector API Reference

All calls use `dynamicInvoke` via `az rest`. Set up your variables first:

```bash
# Load from .env.connectors or construct manually
if [ -f .env.connectors ]; then source .env.connectors; fi
CONN_ID="$SELECTED_OFFICE365_CONNECTOR"
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

For calls that need query parameters, use this variant:

```bash
connector_call_with_queries() {
  local method="$1" path="$2" queries="$3"
  az rest --method POST \
    --url "https://management.azure.com${CONN_ID}/dynamicInvoke?api-version=2016-06-01" \
    --body '{"request":{"method":"'$method'","path":"'$path'","queries":'$queries'}}' \
    --query 'response.body'
}
```

---

## Reading Emails

### List recent emails

```bash
# Get 10 most recent emails from Inbox
connector_call_with_queries GET "/v3/Mail" \
  '{"folderPath":"Inbox","top":"10","fetchOnlyUnread":"true"}'
```

Returns an array of email objects. Each email has:
- `Id` — email ID
- `Subject` — subject line
- `From` — sender email address
- `To` — recipient(s)
- `BodyPreview` — first ~200 chars of the body
- `Body` — full body content
- `DateTimeReceived` — when received
- `IsRead` — read status
- `HasAttachment` — whether it has attachments
- `Importance` — Normal, High, Low

Available query parameters:
- `folderPath` — folder to read from (default: `Inbox`)
- `top` — number of emails to return (as string)
- `fetchOnlyUnread` — `"true"` to get only unread
- `subjectFilter` — filter by subject text
- `from` — filter by sender email

### Get a specific email

```bash
EMAIL_ID="message-id-here"
connector_call GET "/v2/Mail/$EMAIL_ID"
```

---

## Sending Emails

### Send an email

```bash
connector_call POST "/v2/Mail" \
  '{"To":"recipient@example.com","Subject":"Hello!","Body":"<p>This is the email body</p>","Importance":"Normal"}'
```

Optional fields in the body:
- `Cc` — CC recipients (semicolon-separated)
- `Bcc` — BCC recipients (semicolon-separated)
- `Importance` — `Normal`, `High`, or `Low`

The body content is HTML.

### Reply to an email

```bash
EMAIL_ID="message-id-to-reply-to"
connector_call POST "/v3/Mail/ReplyTo/$EMAIL_ID" \
  '{"Body":"<p>Thanks for your email!</p>","ReplyAll":false}'
```

Set `ReplyAll` to `true` to reply to all recipients.

### Forward an email

```bash
EMAIL_ID="message-id-to-forward"
connector_call POST "/codeless/v1.0/me/messages/$EMAIL_ID/forward" \
  '{"ToRecipients":"someone@example.com","Comment":"FYI - see below"}'
```

---

## Managing Emails

### Mark as read

```bash
EMAIL_ID="message-id"
connector_call PATCH "/codeless/v3/v1.0/me/messages/$EMAIL_ID/markAsRead" \
  '{"isRead":true}'
```

### Move to a folder

```bash
connector_call POST "/v2/Mail/Move/$EMAIL_ID" \
  '{"folderPath":"Archive"}'
```

### Delete an email

```bash
connector_call DELETE "/codeless/v1.0/me/messages/$EMAIL_ID"
```

### Flag an email

```bash
connector_call POST "/codeless/v1.0/me/messages/$EMAIL_ID/flag" \
  '{"flag":{"flagStatus":"flagged"}}'
```

---

## Drafts

### Create a draft

```bash
connector_call POST "/Draft" \
  '{"To":"recipient@example.com","Subject":"Draft subject","Body":"<p>Draft body</p>"}'
```

### Send a draft

```bash
DRAFT_ID="draft-message-id"
connector_call POST "/Draft/Send/$DRAFT_ID"
```
