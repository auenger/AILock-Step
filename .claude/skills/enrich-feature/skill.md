---
description: 'Enrich a sub-feature with complete spec, tasks, and checklist by analyzing parent spec, project context, and progressive archive loading.'
---

# Skill: enrich-feature

Enrich a sub-feature (created by `/split-feature`) with complete content. Uses progressive archive loading (Level 1 index scan + Level 2 SubAgent deep-load) to extract implementation patterns from completed features, then fills in User Value Points, Context Analysis, Gherkin scenarios, concrete task breakdown, and checklist.

Also works on any pending feature with incomplete documentation.

## Usage

```
/enrich-feature <feature-id>                  # Enrich single sub-feature
/enrich-feature <parent-id> --all             # Enrich all children of a parent
/enrich-feature <feature-id> --from <doc>     # Use external doc as reference
```

## Pre-flight Checks

1. Feature exists in `feature-workflow/queue.yaml` pending or active list
2. Feature directory exists (`features/pending-{id}/` or `features/active-{id}/`)
3. If `--all`: feature must have children in queue

## Architecture: Progressive Archive Loading

```
enrich-feature (main context)
    │
    ├─ Level 1: Read archive-log.yaml (index, lightweight)
    │   → Extract keywords from target feature name + description
    │   → Match against archived features (keywords, category, related_features)
    │   → Rank by relevance score
    │   → Select top candidates for deep-load
    │
    └─ Level 2: SubAgent deep-load (for top-matched archives)
        │  ← Independent 200k context, parallel execution
        │
        ├─ Read features/archive/done-{id}/spec.md
        ├─ Read features/archive/done-{id}/task.md
        ├─ Extract: implementation patterns, file structures, test conventions
        └─ Return structured context summary
```

## Execution Steps

### Step 1: Load Local Context

Gather all direct source material:

1. **Target feature spec** — `features/pending-{id}/spec.md` (or active)
2. **Parent spec** — if `parent` field is set, read parent's `spec.md`
3. **Sibling specs** — read sibling sub-features' `spec.md` for boundary clarity
4. **External doc** — if `--from <doc>` provided, read it
5. **Project context** — `project-context.md` (if exists)

### Step 2: Level 1 — Archive Index Scan

Read `features/archive/archive-log.yaml`. If file doesn't exist: skip to Step 4.

**Keyword extraction from target feature:**
- Extract from feature `name`, `description`, and parent spec
- Include domain terms (e.g., "company", "factory", "department" for enterprise module)
- Include technical terms if present (e.g., "CRUD", "REST", "component")

**Match logic (same as /query-archive):**

| Match Type | Logic |
|------------|-------|
| Keywords | Case-insensitive match against archived `keywords[]` |
| Name/ID | Case-insensitive substring match against `name` and `id` |
| Category | Exact match if category can be inferred from feature description |
| Related | Bidirectional match via `related_features[]` |
| Dependencies | Check if target's dependencies are completed features |

**Ranking and selection:**

Score each archived feature:
- Keyword overlap count × 3
- Same category × 2
- Direct dependency × 5
- Related feature link × 2

Select **top 3-5** candidates for Level 2 deep-load. Present Level 1 summary:

```
Archive context scan for {id}:

  [Score: 20] feat-auth | User Authentication | 2026-03-02
    keywords: [auth, jwt, login] | category: backend | overlap: 3 keywords

  [Score: 12] feat-rbac | Role-Based Access | 2026-03-10
    keywords: [rbac, permission] | category: backend | overlap: 2 keywords

  [Score: 10] feat-session | Session Management | 2026-03-05
    related: [feat-auth] | category: backend

  → Deep-loading top 3 for implementation patterns...
```

### Step 3: Level 2 — SubAgent Deep Archive Load

Spawn **Agent Tool** (`general-purpose` SubAgent) to deep-load the top-ranked archived features.

**SubAgent prompt template:**

```
You are an Archive Context Agent. Load implementation context from archived features for enriching a new sub-feature.

Target sub-feature: {id} — {name}
Domain keywords: {keywords}

Archived features to analyze: {ranked_ids}

For each archived feature:
1. Glob features/archive/done-{id}-*/ to find the directory
2. Read spec.md → extract: value points, acceptance criteria, data models
3. Read task.md → extract: files created/modified, implementation approach, task breakdown pattern
4. Read checklist.md (if exists) → extract: quality standards used

Return a structured summary for ALL features focusing on:

## Implementation Patterns
- Data model patterns (field naming, relationships, migration approach)
- API patterns (endpoint naming, request/response format, error handling)
- Code organization (directory structure, module boundaries)
- Test patterns (test file naming, mock strategy, coverage targets)

## Reusable Code References
- Files that the new feature should mirror or extend
- Utility functions or base classes that apply
- Configuration patterns (settings, environment variables)

## Boundary Awareness
- What each archived feature owns vs. delegates
- Integration points between features
- Naming conventions used

Be concise but specific. Reference actual file paths and code patterns.
Do NOT return full file contents — only relevant excerpts and patterns.
```

**If SubAgent fails:** fall back to Level 1 index data only. Log warning and continue.

### Step 4: Analyze Enrichment Needs

Scan the target feature's three files to identify what's incomplete:

| File | Check Items |
|------|-------------|
| **spec.md** | User Value Points empty/placeholder? Context Analysis empty? Gherkin scenarios missing? |
| **task.md** | Tasks are `- [ ] ...` placeholders? No concrete items? |
| **checklist.md** | File missing entirely? |

Output a gap report:

```
Enrichment needed for {id}:

spec.md:
  [ ] User Value Points — empty
  [ ] Context Analysis (Reference Code) — empty
  [ ] Context Analysis (Related Documents) — empty
  [ ] Context Analysis (Related Features) — empty
  [ ] Gherkin Scenarios — placeholder only

task.md:
  [ ] Task Breakdown — all placeholders

checklist.md:
  [ ] File missing — will create

Archive context loaded:
  feat-auth: JWT middleware pattern, src/api/auth/ structure
  feat-rbac: decorator-based permission check pattern
```

### Step 5: Enrich spec.md

Using parent spec, project context, codebase analysis, AND archive-derived patterns, fill in:

#### 5.1 User Value Points

Extract the sub-feature's specific value points from the parent spec. Each value point should:
- Be a distinct, testable user capability
- Relate back to the parent spec's value points
- Not overlap with sibling features

#### 5.2 Context Analysis

**Reference Code (enriched with archive patterns):**
- Glob project source to find relevant files (models, APIs, components)
- **Cross-reference archived features**: identify files that follow similar patterns
- List specific files this sub-feature will likely modify, mirror, or extend
- Note existing patterns to follow (extracted from Level 2 deep-load)

Example output:
```markdown
### Reference Code
- src/api/auth/ — JWT middleware pattern (from feat-auth)
- src/models/user.py — SQLAlchemy model example with timestamps
- src/services/base_service.py — CRUD service base class to extend
- src/api/rbac/ — Permission decorator pattern (from feat-rbac)
- tests/test_auth.py — Test file naming and mock strategy
```

**Related Documents:**
- Link to parent spec and sibling specs
- Reference any external docs from `--from`

**Related Features (enriched with archive data):**
- List matched archived features with implementation relevance
- Include bidirectional related_features from archive-log.yaml
- Note dependency chain: which completed features this one builds on

Example output:
```markdown
### Related Features
- feat-auth (completed 2026-03-02) — JWT pattern reused, extends user model
- feat-rbac (completed 2026-03-10) — Permission system to integrate with
- feat-session (completed 2026-03-05) — Session context for company scoping
```

#### 5.3 Gherkin Acceptance Scenarios

Generate complete scenarios for each value point:
- Happy path (1-2 scenarios per value point)
- Error/edge cases (1 scenario per value point)
- Use concrete examples, not abstract descriptions
- For frontend features: include UI interaction steps
- **Informed by archive patterns**: mirror scenario structure from similar completed features

```gherkin
Feature: {sub-feature name}

  Scenario: {scenario name}
    Given {concrete precondition}
    When {specific action}
    Then {verifiable outcome}
```

### Step 6: Enrich task.md

Generate concrete task breakdown based on enriched spec AND archive patterns:

1. Analyze Gherkin scenarios to identify implementation work
2. **Mirror task patterns from archived features** — same category breakdown, similar granularity
3. Break into categories:
   - **Data Layer** — models, migrations, data access
   - **Backend Logic** — API endpoints, business logic, services
   - **Frontend** — UI components, pages, state management (if applicable)
   - **Integration** — cross-component wiring, tests
4. Each task item must be:
   - Specific enough to estimate effort
   - Mapped to at least one Gherkin scenario
   - Ordered by dependency (earlier tasks unblock later ones)
   - **Reference archive patterns**: "Follow feat-auth pattern" or "Mirror src/api/auth/ structure"

Example output:
```markdown
## Task Breakdown

### 1. Data Layer
- [ ] Define Company model (name, address, industry, status) — mirror User model from feat-auth
- [ ] Create migration for companies table (follow migration pattern from feat-auth)
- [ ] Add CompanyRepository with CRUD methods (extend BaseRepository pattern)

### 2. Backend Logic
- [ ] Implement POST /api/companies (follow auth endpoint pattern) — Scenario 1
- [ ] Implement GET /api/companies (list with pagination) — Scenario 2
- [ ] Implement PATCH /api/companies/:id (update) — Scenario 3
- [ ] Add input validation for company fields (reuse validator pattern from feat-auth)

### 3. Testing
- [ ] Unit tests for CompanyRepository (follow test_auth.py pattern)
- [ ] API integration tests for CRUD endpoints
```

### Step 7: Create checklist.md

If missing, create from template at `feature-workflow/templates/checklist.md`.

Customize checklist items based on:
- **Feature type**: backend (unit tests, API validation), frontend (UI testing, responsiveness), fullstack (both)
- **Archive quality standards**: if deep-loaded archives show specific coverage targets or test patterns, include those

### Step 8: Confirm and Write

Present the enriched content for review. User can:
- **Approve**: write all files
- **Edit**: adjust specific sections before writing
- **Partial**: approve some files, skip others

In `--auto` mode (called by split-feature or dev-agent): write directly without confirmation.

### Step 9: Update Progress Log

Append to `task.md` progress log:

```markdown
| {date} | Spec enriched | Value points: {N}, Scenarios: {N}, Tasks: {N}, Archive refs: {N} |
```

## Batch Mode (--all)

When called with `--all` on a parent feature:

1. Read parent spec and all children specs
2. **Single Level 1 scan** — one archive-log.yaml read, match against all children
3. **Parallel Level 2 deep-load** — single SubAgent loads all relevant archives at once
4. For each child, execute Steps 4-8 using shared archive context
5. Ensure sibling boundaries are clear (no overlapping value points or tasks)
6. Output summary:

```
Enriched {N} sub-features under {parent_id}:

  {child1}: 3 value points, 8 scenarios, 12 tasks (archive refs: feat-auth, feat-rbac)
  {child2}: 2 value points, 5 scenarios, 9 tasks (archive refs: feat-auth)
  {child3}: 2 value points, 6 scenarios, 10 tasks (archive refs: feat-session)

Total: 7 value points, 19 scenarios, 31 tasks
Sibling overlap check: OK
Archive context: 4 features deep-loaded, 2 index-only
```

## Integration with split-feature

`/split-feature` can auto-call `/enrich-feature --all` after completing the split (Step 8). This is controlled by `feature-workflow/config.yaml`:

```yaml
workflow:
  splitting:
    auto_enrich: true   # default: true
```

When `auto_enrich: true`, split-feature appends this to its Step 8:
> After queue update, invoke `/enrich-feature {parent_id} --all` to fill all sub-feature documents.

## Output

```
Feature enriched: {id}

Archive context:
  Level 1: {N} features scanned
  Level 2: {N} features deep-loaded → {summary of key patterns}

spec.md:
  + User Value Points: {N} points
  + Context Analysis: {M} reference files, {K} related features
  + Gherkin Scenarios: {S} scenarios (informed by {archive_pattern_refs})

task.md:
  + {T} concrete tasks across {C} categories
  + Archive-mirrored patterns: {list}

checklist.md:
  + Created with {F} items

Files updated:
  features/pending-{id}/spec.md
  features/pending-{id}/task.md
  features/pending-{id}/checklist.md (created)
```

## Error Handling

| Error | Description | Solution |
|-------|-------------|----------|
| NOT_FOUND | Feature ID not in queue | Check ID, use /list-features |
| NO_PARENT | Feature has no parent and no --from doc | Provide --from or use on child features |
| ALREADY_COMPLETE | All sections already filled | Use --force to overwrite |
| CONTEXT_MISSING | No project-context.md and no parent spec | Run /pm-agent first or provide --from |
| NO_ARCHIVES | archive-log.yaml doesn't exist | Skip archive context, enrich from parent spec only |
| SUBAGENT_FAILED | Level 2 deep-load failed | Fall back to Level 1 index data, continue enrichment |
| WRITE_ERROR | Cannot write to feature directory | Check permissions |

## Notes

1. **Progressive loading** — Level 1 (index scan) is always fast; Level 2 (SubAgent) only fires for top-ranked archives
2. **Archive patterns inform, not dictate** — extracted patterns guide task breakdown but don't override feature-specific needs
3. **Parent as source of truth** — enrichment derives from parent spec, archives add implementation context
4. **Sibling boundary clarity** — each child gets non-overlapping value points and tasks
5. **Concrete over abstract** — task items reference specific files, APIs, models, and archive patterns
6. **Idempotent** — running twice won't duplicate content, only fill missing sections
7. **Works standalone** — not limited to split-feature output; can enrich any incomplete feature
8. **Graceful degradation** — if no archives exist or SubAgent fails, enrichment continues with parent spec + project context only
