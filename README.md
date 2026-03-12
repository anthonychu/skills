# Skills

My collection of custom skills for AI coding agents.

- [Azure Connectors](#azure-connectors) — Work with Office 365 email and Microsoft Teams via Azure connectors
- [Git Tutor](#git-tutor) — Interactive git & GitHub tutor with gamification

## [Azure Connectors](skills/azure-connectors/)

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

## [Git Tutor](skills/git-tutor/)

Interactive git and GitHub tutor that teaches through hands-on practice in VS Code's terminal. Adapts to any skill level — from someone who's never opened a terminal to experienced developers filling knowledge gaps. Features gamification with XP, streaks, achievements, and challenges.

**Getting started:**

1. Open a terminal and create a new folder:
   ```bash
   mkdir git-playground && cd git-playground
   ```
2. Install the skill (see [Skills docs](https://github.com/vercel-labs/skills) for details):
   ```bash
   npx skills add https://github.com/anthonychu/skills --skill git-tutor
   ```
3. Open the folder in VS Code:
   ```bash
   code .
   ```
4. Open VS Code's chat panel (Ctrl+Shift+I / Cmd+Shift+I) and say something like "I want to learn git" or type `/git-tutor` to start the tutorial

**Capabilities:**
- Adaptive skill assessment and personalized lesson flow
- Hands-on exercises in the real workspace with full transparency
- Covers git fundamentals, branching, merging, rebasing, GitHub workflows, and more
- Real-world scenario challenges (merge conflicts, history rewriting, recovery)
- Gamification: XP, levels, daily streaks, achievements, and hidden easter eggs
- Checkpoints (knowledge checks) and flashbacks (spaced repetition)
- Personalized cheatsheet built as you learn
- Progress tracking in `.git-tutor/` folder
