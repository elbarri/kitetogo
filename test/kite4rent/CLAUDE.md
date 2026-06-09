# Kitesurf WhatsApp - Development Guidelines

## Project Overview
This is an Elixir/Phoenix application serving as a contacts marketplace for kitesurfing gear rentals. Users can offer and rent equipment including boards, kites, leashes, harnesses, and other essential gear.

## Development Environment

### asdf Version Manager
This project uses **asdf** to manage runtime versions (Elixir, Erlang, Node.js, etc.). The asdf shims are automatically added to PATH when the shell starts.

- **asdf is installed** at `/opt/homebrew/opt/asdf/`
- **Important**: When running shell commands that require Elixir/Erlang (like `mix`, `iex`, `elixir`), asdf shims are available in the PATH automatically
- Version specifications are in `.tool-versions` file in the project root
- If you encounter "command not found" errors for `mix` or `elixir`, ensure asdf is sourced in your shell

### direnv - Environment Configuration
This project uses **direnv** to automatically load environment variables from `.envrc` and `.envrc.private` files.

- **direnv is installed** and configured to automatically load/unload environment when entering/leaving the project directory
- `.envrc` contains project configuration and is committed to git
- `.envrc.private` contains sensitive credentials (API keys, tokens) and is gitignored
- When you `cd` into the project directory, direnv automatically exports all variables from these files
- **Important environment variables** loaded by direnv:
  - `WHATSAPP_ACCESS_TOKEN` - WhatsApp Cloud API access token
  - `WHATSAPP_PHONE_ID` - WhatsApp phone number ID (environment-specific)
  - `WHATSAPP_BUSINESS_ACCOUNT_ID` - WhatsApp Business Account ID
  - Various other API keys and configuration

### Running Commands
When executing shell commands in this project, asdf and direnv are already configured:

```bash
# These commands work directly (no setup needed)
mix test
mix phx.server
iex -S mix

# Environment variables are automatically loaded
echo $WHATSAPP_ACCESS_TOKEN  # Works without manual sourcing
```

## Core Development Principles

### Testing & CI/CD
- **Always run tests after modifications**: Execute `mix test` after every code change
- **Fix failing tests immediately**: Update and maintain test coverage properly
- **Follow CI/CD practices**: All changes should integrate seamlessly into the deployment pipeline

### Code Architecture
- **Context-driven design**: Leverage Phoenix contexts (`mix phx.gen.context`) for proper domain separation
- **Modular structure**: Organize code by business domains (e.g., Users, Gear, Rentals, Payments)
- **Scalability focus**: Write code that supports future feature additions without major refactoring

### Software Engineering Standards
- **Separation of Concerns**: Each module should have a single, well-defined responsibility
- **Single Responsibility Principle**: Functions and modules should do one thing well
- **DRY Principle**: Eliminate code duplication through proper abstraction
- **Self-documenting code**: Write clear, expressive code that doesn't require inline comments

### Elixir/Phoenix Best Practices
- Use appropriate Phoenix generators for consistency
- Follow Elixir naming conventions and patterns
- Implement proper error handling with pattern matching
- Utilize GenServers and OTP principles where appropriate
- Structure code following Phoenix directory conventions

### Error handling
- Use Logger.error directly for error logging with structured metadata (error:, reason:, etc.)
- Tests should validate behavior through return values, not by mocking Logger.error

### Quality Assurance
- Maintain high test coverage
- Use Credo for code quality checks
- Follow Elixir formatter standards
- Ensure all functions have proper typespecs where beneficial
- Don't code integration tests; only unit testing with proper mocks using the library Mimic

## Workflow
1. Make code changes following the above principles
2. Run `mix test` to verify functionality
3. Fix any failing tests and update as needed
4. Ensure code follows architectural guidelines
5. Verify changes don't break existing functionality

## Prod Message Analysis Workflow
When asked to analyze user interactions from production:
1. Query prod DB via the `prod-db` MCP server (read-only Postgres on localhost:5433 via SSH tunnel to Coolify)
2. Key tables: `whatsapp_messages` (has `content` jsonb with `body`, `llm_response`), `users` (has `phone_number`, `location_name`, `language`)
3. Identify UX problems: failed intents, wrong language responses, repeated location asks, missing data, LLM errors
4. Group issues by root cause, propose fixes with file/line references
5. Enter plan mode for user approval before implementing
6. After implementation: `mix compile --warnings-as-errors`, `mix test`, commit
7. **Start a new Claude session for each batch** — avoids context bloat and keeps costs down

### Useful queries
```sql
-- Recent messages for a user (by phone)
SELECT id, type, content->>'body' as body, content->'llm_response'->>'intention' as intent,
       content->'llm_response'->>'language' as lang, inserted_at
FROM whatsapp_messages WHERE phone_number = '+XXXXX' ORDER BY id;

-- Messages in a range
SELECT id, phone_number, type, content->>'body' as body,
       content->'llm_response'->>'intention' as intent, inserted_at
FROM whatsapp_messages WHERE id BETWEEN X AND Y ORDER BY id;

-- Failed intents (no llm_response)
SELECT id, phone_number, content->>'body' as body, inserted_at
FROM whatsapp_messages WHERE is_incoming = true AND content->'llm_response' IS NULL
ORDER BY id DESC LIMIT 20;
```

