# Skills

My collection of custom skills for AI coding agents.

## Available Skills

### [Azure Connectors](skills/azure-connectors/)

Work with Azure managed API connectors (Office 365 and Microsoft Teams) to send emails, read emails, post Teams messages, reply to threads, and list channels. Handles creating and authenticating connector resources, and remembers your selections in a `.env.connectors` file so you only configure once per repo.

**Install:**
```bash
npx skills add https://github.com/anthonychu/skills --skill azure-connectors
```

**Capabilities:**
- Send, read, reply to, and manage emails via Office 365
- Post and reply to messages in Teams channels
- Create and authenticate new connector resources
- Interactive connector discovery (subscription and connector selection)
- Persistent connector configuration via `.env.connectors`
