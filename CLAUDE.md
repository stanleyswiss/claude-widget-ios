# === COGNILAYER (auto-generated, do not delete) ===

## CogniLayer v4 Active
Persistent memory + code intelligence is ON.
ON FIRST USER MESSAGE in this session, briefly tell the user:
  'CogniLayer v4 active — persistent memory is on. Type /cognihelp for available commands.'
Say it ONCE, keep it short, then continue with their request.

## MEMORY HIERARCHY (CRITICAL — ALWAYS FOLLOW)

You have TWO memory systems. Use BOTH, but with clear priority:

### PRIMARY: CogniLayer MCP (memory_search / memory_write)
- ALWAYS use FIRST for both reading and writing
- FTS5 + vector search, heat decay, 14 fact types, code intelligence
- On-demand — loads only relevant facts (~500 tokens instead of tens of thousands)
- Store here: decisions, gotchas, patterns, error_fixes, api_contracts, procedures

### SECONDARY (FALLBACK): Auto-memory (MEMORY.md files)
- Use when CogniLayer MCP is unavailable, fails, or returns empty
- MEMORY.md is loaded into context ALWAYS at session start — keep it SHORT (max 30 lines)
- Store here only: critical user feedback, deploy workflow, 1-line pointers to CogniLayer

### RULES:
1. READING: memory_search(query) FIRST → if empty/error → read MEMORY.md files
2. WRITING: memory_write() ALWAYS → ALSO to auto-memory ONLY if critical user feedback/rule
3. NEVER duplicate content — if fact is in CogniLayer, put only a 1-line pointer in auto-memory
4. Auto-memory MEMORY.md is an INDEX, not a database — format: `- [topic] → /recall keyword`
5. If CogniLayer MCP fails → USE auto-memory as base and alert user about MCP issue

### CHECK (every ~10 prompts or before ending work):
- Did I save new findings to memory_write()? If not → save NOW
- Is session bridge current? If not → session_bridge(action="save")
- DO NOT wait for end of session — save continuously, session may crash

## Tools — HOW TO WORK

FIRST RUN ON A PROJECT:
When DNA shows "[new session]" or "[first session]":
1. Run /onboard — indexes project docs (PRD, README), builds initial memory
2. Run code_index() — builds AST index for code intelligence
Both are one-time. After that, updates are incremental.
If file_search or code_search return empty → these haven't been run yet.

UNDERSTAND FIRST (before making changes):
- memory_search(query) → what do we know? Past bugs, decisions, gotchas
- code_context(symbol) → how does the code work? Callers, callees, dependencies
- file_search(query) → search project docs (PRD, README) without reading full files
- code_search(query) → find where a function/class is defined
Use BOTH memory + code tools for complete picture. They are fast — call in parallel.

BEFORE RISKY CHANGES (mandatory):
- Renaming, deleting, or moving a function/class → code_impact(symbol) FIRST
- Changing a function's signature or return value → code_impact(symbol) FIRST
- Modifying shared utilities used across multiple files → code_impact(symbol) FIRST
- ALSO: memory_search(symbol) → check for related decisions or known gotchas
Both required. Structure tells you what breaks, memory tells you WHY it was built that way.

AFTER COMPLETING WORK:
- memory_write(content) → save important discoveries immediately
  (error_fix, gotcha, pattern, api_contract, procedure, decision)
- session_bridge(action="save", content="Progress: ...; Open: ...")
DO NOT wait for /harvest — session may crash.

## SHORT SESSIONS = BETTER PERFORMANCE
- With 200K context, session compresses sooner → faster responses
- CogniLayer bridge + memory_search replaces lost history for ~2K tokens
- After completing a coherent block of work: save bridge → suggest user starts new session
- Use /compact when session grows and work is not yet done

SUBAGENT MEMORY PROTOCOL:
When spawning Agent tool for research or exploration:
- Include in prompt: synthesize findings into consolidated memory_write(content, type, tags="subagent,<task-topic>") facts
  Assign a descriptive topic tag per subagent (e.g. tags="subagent,auth-review", tags="subagent,perf-analysis")
- Do NOT write each discovery separately — group related findings into cohesive facts
- Write to memory as the LAST step before return, not incrementally — saves turns and tokens
- Each fact must be self-contained with specific details (file paths, values, code snippets)
- When findings relate to specific files, include domain and source_file for better search and staleness detection
- End each fact with 'Search: keyword1, keyword2' — keywords INSIDE the fact survive context compaction
- Record significant negative findings too (e.g. 'no rate limiting exists in src/api/' — prevents repeat searches)
- Return: actionable summary (file paths, function names, specific values) + what was saved + keywords for memory_search
- If MCP tools unavailable or fail → include key findings directly in return text as fallback
- Launch subagents as foreground (default) for reliable MCP access — user can Ctrl+B to background later
Why: without this protocol, subagent returns dump all text into parent context (40K+ tokens).
With protocol, findings go to DB and parent gets ~500 token summary + on-demand memory_search.

BEFORE DEPLOY/PUSH:
- verify_identity(action_type="...") → mandatory safety gate
- If BLOCKED → STOP and ask the user
- If VERIFIED → READ the target server to the user and request confirmation

## VERIFY-BEFORE-ACT
When memory_search returns a fact marked ⚠ STALE:
1. Read the source file and verify the fact still holds
2. If changed → update via memory_write
3. NEVER act on STALE facts without verification

## Process Management (Windows)
- NEVER use `taskkill //F //IM node.exe` — kills ALL Node.js INCLUDING Claude Code CLI!
- Use: `npx kill-port PORT` or find PID via `netstat -ano | findstr :PORT` then `taskkill //F //PID XXXX`

## Git Rules
- Commit often, small atomic changes. Format: "[type] what and why"
- commit = Tier 1 (do it yourself). push = Tier 3 (verify_identity).

## Project DNA: claude-widget
Stack: unknown
Style: [unknown]
Structure: ?
Deploy: [NOT SET]
Active: [new session]
Last: [first session]

# === END COGNILAYER ===
