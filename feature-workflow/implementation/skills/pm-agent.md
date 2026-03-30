---
description: 'Build or update project-context.md - the shared knowledge base for AI agents working on this project.'
---

# Skill: pm-agent

Build, update, or refresh `project-context.md` — the shared knowledge base that all AI agents reference when implementing features. This file contains critical rules, patterns, and conventions that prevent AI from making mistakes.

## Usage

```
/pm-agent                    # Build or update project context
/pm-agent --fresh            # Rebuild from scratch (full analysis)
/pm-agent --check            # Check if context is up-to-date
/pm-agent --section=rules    # Update only a specific section
```

## Pre-flight Checks

### Check 1: Feature Workflow Initialized

- `feature-workflow/config.yaml` must exist
- If not: suggest running `/init-project` first

### Check 2: Project Context Exists

- Check for `project-context.md` in project root
- If exists: offer to **update** (incremental) or **rebuild** (fresh)
- If not: proceed with **build** (full analysis)

## Execution Steps

### Step 1: Load Configuration

Read `feature-workflow/config.yaml`:
- `project.name` — project display name
- `project.tech_stack` — for accurate detection
- `project.test_framework` — test patterns section

### Step 2: Deep Project Analysis

Perform comprehensive scan of the project:

#### 2.1 Technology Stack Detection

```
Priority scan:
1. pyproject.toml → [tool.poetry] / [project] → Python version, dependencies
2. package.json → engines, dependencies, devDependencies → Node version
3. requirements.txt → Python packages
4. go.mod → Go version
5. Cargo.toml → Rust version

Result: Full technology stack table
```

#### 2.2 Directory Structure Mapping

```
Scan:
1. Top-level directories (ls -d */)
2. Key subdirectories (src/*, tests/*, etc.)
3. Special directories (migrations/, static/, templates/)

Generate: ASCII directory tree (2-3 levels)
```

#### 2.3 Code Pattern Analysis

Scan representative source files to identify:

**Naming Conventions:**
- File naming: snake_case, camelCase, kebab-case, PascalCase
- Class naming: PascalCase, prefix pattern
- Function naming: snake_case, camelCase
- Variable naming: snake_case, camelCase
- Constant naming: UPPER_SNAKE_CASE

**Import Patterns:**
- Import style (absolute vs relative)
- Module organization (barrel exports, index files)
- Third-party import grouping

**Error Handling:**
- Exception types used
- Error handling pattern (try/catch, Result type, etc.)
- Logging patterns

**Code Style:**
- Indentation (tabs vs spaces)
- Quotes (single vs double)
- Semicolons (present or absent)
- Line length conventions

#### 2.4 Test Pattern Analysis

```
Scan:
1. Test directory structure (tests/, __tests__/, *_test.*, test_*.py)
2. Test framework (from config or detection)
3. Test naming pattern
4. Mock/stub patterns
5. Test fixtures usage
```

#### 2.5 Architecture Pattern Detection

```
Detect:
1. Architecture style (MVC, Clean Architecture, hexagonal, etc.)
2. Dependency injection pattern
3. State management pattern
4. API style (REST, GraphQL, RPC)
5. Database access pattern (ORM, raw SQL, repository)
```

#### 2.6 Recent Changes Analysis

```
1. Read feature-workflow/queue.yaml completed list (last 5 features)
2. Read features/archive/archive-log.yaml (last 10 records)
3. Extract: feature IDs, names, completion dates, value points
4. Generate recent changes table
```

### Step 3: Identify Critical Rules

Based on code analysis, identify:

**Must Follow (Rules):**
- Framework-specific conventions
- Security requirements (auth, input validation)
- Performance patterns (caching, pagination)
- Project-specific patterns that are non-obvious

**Must Avoid (Anti-patterns):**
- Common mistakes found in codebase
- Framework anti-patterns
- Deprecated patterns
- Known performance pitfalls

### Step 4: Generate/Update project-context.md

#### Build Mode (New File)

Generate complete `project-context.md` using all analysis results:

```markdown
---
last_updated: '{ISO_DATE}'
version: 1
features_completed: {COUNT}
---

# Project Context: {PROJECT_NAME}

> This file contains critical rules and patterns that AI agents must follow
> when implementing code. Keep it concise and focused on non-obvious details.

---

## Technology Stack

| Category | Technology | Version | Notes |
|----------|-----------|---------|-------|
| Language | {detected} | {version} | {notes} |
| Framework | {detected} | {version} | {notes} |
| Database | {detected} | {version} | {notes} |
| Testing | {detected} | {version} | {notes} |

## Directory Structure

{ASCII_TREE}

## Critical Rules

### Must Follow

- Rule 1: {detected_rule}
- Rule 2: {detected_rule}

### Must Avoid

- Anti-pattern 1: {detected_antipattern}
- Anti-pattern 2: {detected_antipattern}

## Code Patterns

### Naming Conventions

- Files: {detected_pattern}
- Classes: {detected_pattern}
- Functions: {detected_pattern}
- Constants: {detected_pattern}

### Import Patterns

{CODE_EXAMPLE}

### Error Handling

{CODE_EXAMPLE}

## Testing Patterns

### Unit Tests

- Location: {detected_path}
- Naming: {detected_pattern}
- Framework: {detected_framework}

### Integration Tests

- Location: {detected_path}

## Recent Changes

| Date | Feature | Impact |
|------|---------|--------|
| {data from queue.yaml} | | |

## Update Log

- {DATE}: Initial project context created
```

#### Update Mode (Incremental)

Read existing `project-context.md`, then:

1. **Update Recent Changes** — Add newly completed features from `queue.yaml`
2. **Update Tech Stack** — If new dependencies detected (compare package.json/pyproject.toml)
3. **Update Rules** — If user provides new rules or patterns changed
4. **Update Version** — Increment version, update last_updated

Only modify sections that changed. Preserve manually added content.

#### Section Mode (`--section=rules`)

Update only the specified section:

| Section | What Updates |
|---------|-------------|
| `stack` | Technology stack table |
| `rules` | Critical rules and anti-patterns |
| `patterns` | Code patterns and naming |
| `testing` | Test patterns |
| `changes` | Recent changes from queue |
| `structure` | Directory structure |

### Step 5: Validation

Verify the generated `project-context.md`:
- All sections have content (not just placeholders)
- Technology stack is accurate
- Code examples are from actual project files
- Recent changes match queue.yaml

### Step 6: Summary

Report what was generated/updated.

## Check Mode (`--check`)

Compare current project state against project-context.md:

```
Project Context Health Check
-----------------------------
✓ Tech stack: matches (python-311)
⚠ New dependencies: 3 untracked (black, ruff, httpx)
✓ Directory structure: up to date
✓ Code patterns: 2 samples verified
⚠ Recent changes: 5 features behind

Recommendation: Run /pm-agent to update
```

## Output

### Success - Build

```
Project context built!

File: project-context.md
Size: 2.3 KB

Sections:
  ✓ Technology Stack (5 entries)
  ✓ Directory Structure
  ✓ Critical Rules (3 must-follow, 2 anti-patterns)
  ✓ Code Patterns (naming, imports, error handling)
  ✓ Testing Patterns
  ✓ Recent Changes (5 features)

Run /new-feature to start developing!
```

### Success - Update

```
Project context updated!

Changes:
  + 3 new dependencies in tech stack
  + 5 recent features added
  ~ Anti-patterns section updated
  - No removed content
```

## Error Handling

| Error | Description | Solution |
|-------|-------------|----------|
| NOT_INITIALIZED | feature-workflow not initialized | Run /init-project first |
| EMPTY_PROJECT | No source files to analyze | Create project structure first |
| PERMISSION_ERROR | Cannot write project-context.md | Check filesystem permissions |
| DETECTION_FAILED | Cannot determine tech stack | Manually specify in config.yaml |

## Notes

1. **Run after init** — Always run after `/init-project` to build the initial context
2. **Run after complete** — Optionally run after `/complete-feature` to update recent changes
3. **Keep concise** — The file should be <200 lines to avoid consuming too much context
4. **Human-editable** — Users can manually add rules and patterns
5. **Non-destructive update** — Incremental updates preserve manual additions
6. **Source of truth** — This file is the primary reference for all AI agents
