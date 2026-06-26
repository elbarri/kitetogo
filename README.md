# KiteToGo
A production WhatsApp AI agent marketplace where kitesurfers rent gear from each other. 

The agent is the primary interface: users describe their needs, the agent understands them, when needed asks follow-up questions, and guides them through either completing a listing or finding gear.

It uses a **custom orchestration framework**, generating conversational responses with **LangChain** for tool-using/function-calling/MCP Server like functionality by applying IoC concepts to language models.

I chose Elixir to build the **orchestration layer** because Erlang/OTP solved the hard distributed systems problems (supervision, isolation, message passing) in the 80s and 90s, and those are exactly the patterns the agentic AI field is now converging on.

The hard unsolved problems are specifically about LLM non-determinism, trust, and semantic correctness. I address them coordinating how LLM calls are sequenced, how results flow between components, how routing decisions are made, and how multi-turn state is managed.

Specifically:

- The parallel extraction (Task.async_many over intent + gear + location) is custom code
- The routing logic (rules engine → intent handler → flow handler) is custom
- The conversation state machine (what step are we on, what's missing, what's next) is custom, persisted via Ecto to Postgres
- The LLM fallback chain (try OpenRouter → Gemini → Haiku → Llama) is custom HTTP logic
- The feature-flag-gated rollout of new extractors is custom

---

## Architecture TLDR

When a user sends a message, the agent runs a **parallel extraction pipeline**. Based on the classified intent and confidence score, a **rules engine routes the message** to specialized handlers. For ambiguous or conversational messages, it delegates to a **LangChain-powered tool-using** handler that calls real database functions (gear availability, locations) rather than hallucinating answers. For complex operations like publishing gear or collecting a security deposit, the agent enters multi-step conversation flows — persistent state machines backed by PostgreSQL so they survive application restarts.

## Architecture 

The agent processes every incoming WhatsApp message through a layered pipeline:

**1. Audio → Text (when needed)**
Voice messages are transcribed via AssemblyAI or a local Whisper instance before entering the pipeline.

**2. Parallel Extraction**
Three LLM calls fire concurrently using `Task.async_many`:
- **Intent classifier** — outputs one of 8 intents (`offer_gear`, `request_gear`, `check_availability`, etc.) with a confidence score (0.0–1.0) and a `doubt_asked_likelihood` score
- **Gear extractor** — pulls structured entities: gear type, brand, model, size, year, condition — validated against known brand reference tables
- **Location extractor** — extracts a named place with confidence, filtering out vague phrases like "around here"

All extractors use **InstructorLite** (an Elixir library) to force the LLM into validated, schema-typed outputs via structured output / JSON mode.

**3. Intent Routing**
A **rules engine** (Wongi, a Rete-based engine) asserts facts from the extracted data and dispatches to the appropriate handler. If confidence is below 0.75 or the user is asking a question (`doubt_asked_likelihood ≥ 0.6`), the message is redirected to the conversational handler.

**4. Intent Handlers**
Each intent has a dedicated handler. The most complex is the **ChatHandler**, which uses LangChain with function calling. The LLM has access to tools it must call rather than guess: `search_locations`, `get_gear_availability`, `get_feature_guide`. The system prompt explicitly instructs it to never assume data exists — always call the tools.

**5. Multi-Step Conversation Flows**
For complex operations (publishing gear, collecting a deposit), the agent enters a **state machine flow** persisted to PostgreSQL. Each flow tracks which fields have been collected, which are missing, and what step the user is on. This survives application restarts — a deliberate choice over in-memory GenServers.

**6. Language Detection & Translation**
The pipeline auto-detects the user's language. For the 6 natively supported languages (EN, ES, FR, DE, NL, IT), responses are rendered from templates. For anything else, an LLM call translates on the fly using few-shot examples.

---

## The Agent's Responsibilities

- Understanding free-text gear descriptions in any language and turning them into structured listings
- Routing ambiguous messages to a conversational handler that asks clarifying questions
- Managing multi-turn dialogues to collect missing information without losing context across sessions
- Matching renters with available gear based on type, size, and location
- Handling security deposit flows end-to-end
- Dynamically labeling users as schools vs. individuals based on behavioral signals

---

## Tools and Data Sources

| Tool / Source | Purpose |
|---|---|
| **OpenRouter** | Primary LLM provider (structured extraction + chat) |
| **Gemini / Claude Haiku / Llama** | Automatic fallback if OpenRouter fails |
| **InstructorLite** | Structured output extraction with Ecto schema validation |
| **LangChain (Elixir)** | Tool-calling loop in the conversational handler |
| **AssemblyAI + Whisper** | Audio transcription |
| **Nominatim** | Geocoding location strings to coordinates |
| **PostgreSQL + PostGIS** | Gear listings, conversation state, spatial proximity queries |
| **WhatsApp Business Cloud API** | Inbound/outbound message transport |

---

## Deployment

The agent runs on a **Hetzner VPS** managed via **Coolify** (self-hosted PaaS). It's packaged as a Docker container built from an Elixir release. PostgreSQL runs in a separate container on the same host with PostGIS and pgvector extensions.

Deployments are triggered via Coolify's webhook integration — push to `master`, the container rebuilds and restarts with zero-downtime swap.

---

## Main Production Challenges

**1. Stale Docker build cache serving old BEAM files**
After a refactor, the deployed container was still running old code because Docker cached the compiled artifacts. The fix required running `docker builder prune -af` to force a full rebuild. Now we treat suspicious behavior post-deploy as a cache issue first.

**2. OTP 28 crashing on empty DNS labels**
Upgrading to OTP 28 introduced a crash in `:inet_dns.encode_labels/4` when DNS responses contained empty labels — a subtle BEAM runtime bug, not application code. Required patching the DNS configuration in the release environment.

**3. Coolify pre-deployment commands running on the crashing container**
If the app container was crash-looping, Coolify's pre-deployment hooks (which run on the *existing* container) would fail instantly, making it impossible to deploy a fix. The workaround was to SSH in and manually bring the container to a stable state before triggering deployment.

**4. Structured extraction reliability**
Early versions used free-text LLM responses and then tried to parse them. Switching to InstructorLite with strict Ecto schemas (with validation changesets) eliminated an entire class of parse errors and made the extraction deterministic enough for production.

**5. Conversation state surviving restarts**
The naive approach of keeping conversation flow state in a GenServer meant every deploy wiped in-progress user conversations. Moving state to PostgreSQL with a 24-hour TTL solved this — users can pick up a conversation after a deploy without noticing anything.
