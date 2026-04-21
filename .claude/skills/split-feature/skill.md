---
description: 'Split a large feature into sub-features, convert original to module index, and update queue.yaml.'
---

# Skill: split-feature

Split an existing feature into smaller sub-features based on requirement analysis. The original feature is converted into a module-level index that references all sub-features.

## Usage

```
/split-feature <feature-id>           # Interactive: analyze spec and propose split
/split-feature <feature-id> --from <doc-path>  # Split based on external requirement doc
```

## Execution Steps

### Step 1: Load Feature

1. Read `feature-workflow/queue.yaml` to find the feature entry
2. Read `features/pending-{id}/spec.md` (or `active-{id}`)
3. If `--from <doc-path>` provided, read the external requirement document

### Step 2: Analyze and Propose Split

Analyze the feature spec (and external doc if provided) to identify independent sub-features.

**Split criteria:**
- Each sub-feature should be independently deliverable
- Each sub-feature should have clear data model boundaries
- Group by business domain, not technical layers
- Target size: S or M (avoid creating new L features)

**Output a split proposal in this format:**

```
Split Proposal for {id}
─────────────────────────────────
Original: {name} (L)

Sub-features:
  1. {id}-xxx  {name}  [M]  depends: []
  2. {id}-yyy  {name}  [S]  depends: [{id}-xxx]
  3. {id}-zzz  {name}  [M]  depends: []
  ...

Dependency chain:
  {visual tree}

Confirm? [Y/n/edit]
```

### Step 3: Confirm with User

Present the proposal and wait for confirmation. User can:
- **Confirm**: proceed with the split
- **Edit**: adjust names, dependencies, or granularity
- **Cancel**: abort the operation

### Step 4: Generate Sub-Feature IDs

- Format: descriptive slug, not necessarily `{parent}-{suffix}`
- Example: parent `feat-enterprise-org` -> children `feat-company`, `feat-factory`, `feat-department`
- ID should be self-descriptive and meaningful on its own
- Prefix from `feature-workflow/config.yaml` `naming.feature_prefix` (default "feat")

### Step 5: Create Sub-Feature Directories

For each sub-feature, create `features/pending-{id}/` with:

**spec.md:**
```markdown
# Feature: {id} {name}

## Basic Information
- **ID**: {id}
- **Name**: {name}
- **Priority**: {priority}
- **Size**: {S|M}
- **Dependencies**: {dependencies}
- **Parent**: {parent_id}
- **Children**: (empty)
- **Created**: {timestamp}

## Description
{business requirements from analysis}

## User Value Points
{value points for this sub-feature}

## Context Analysis
### Reference Code
### Related Documents
### Related Features

## Technical Solution
<!-- To be filled during implementation -->

## Acceptance Criteria (Gherkin)
### User Story
### Scenarios (Given/When/Then)
### General Checklist
```

**task.md:**
```markdown
# Tasks: {id}

## Task Breakdown
### Backend
- [ ] ...

### Frontend
- [ ] ...

### General
- [ ] ...

## Progress Log
| Date | Progress | Notes |
|------|----------|-------|
| {date} | Split created | Split from {parent_id} |
```

### Step 6: Convert Original Feature to Module Index

Rewrite the original feature's `spec.md` to be a module index:

```markdown
# Feature: {id} {name}

## Basic Information
- **ID**: {id}
- **Name**: {name}
- **Priority**: {priority}
- **Size**: L (module-level)
- **Dependencies**: {dependencies}
- **Parent**: (empty)
- **Children**: [{child1}, {child2}, ...]
- **Created**: {original_date}

## Description
{high-level module description}

## Sub-Feature List

| ID | Name | Priority | Size | Dependencies |
|----|------|----------|------|--------------|
| [{child1}](../pending-{child1}/spec.md) | {name} | {p} | {s} | {deps} |
| [{child2}](../pending-{child2}/spec.md) | {name} | {p} | {s} | {deps} |

## Dependency Graph
{visual dependency tree}

## Module Progress
| Sub-Feature | Status | Notes |
|-------------|--------|-------|
| {child1} | pending | |
| ... | | |
```

Rewrite the original feature's `task.md`:

```markdown
# Tasks: {id}

> This is a module-level feature. Development progresses through sub-features.

## Sub-Feature Progress

- [ ] [{child1}](../pending-{child1}/task.md) — {name}
- [ ] [{child2}](../pending-{child2}/task.md) — {name}

## Completion Criteria
Module feature is marked complete when all sub-features are completed.

## Progress Log
| Date | Progress | Notes |
|------|----------|-------|
| {date} | Module split completed | Split into N sub-features |
```

### Step 7: Update queue.yaml

Read `feature-workflow/queue.yaml` and update:

1. **Move parent to `parents` section** — add `children: [child_ids]` field, set status
2. **Add sub-feature entries** to `pending` list — each with `parent: {parent_id}`, proper priority and dependencies
3. **Update downstream dependencies** — other features that depended on the parent should keep depending on the parent (not individual children)
4. **Sort** pending list by priority descending
5. **Update** `meta.last_updated`

**queue.yaml entry format:**

```yaml
# Parent entry (in parents section)
- id: feat-enterprise-org
  name: "Enterprise Management Module"
  description: "..."
  priority: 90
  size: L
  status: pending
  children:
    - feat-company
    - feat-factory
    - feat-department

# Child entries (in pending list)
- id: feat-company
  name: "Company Management"
  priority: 95
  size: M
  parent: feat-enterprise-org
  dependencies: []

- id: feat-factory
  name: "Factory Management"
  priority: 94
  size: M
  parent: feat-enterprise-org
  dependencies:
    - feat-company
```

### Step 8: Verify Consistency

After all changes, verify:
1. Every child ID in parent's `children` list has a corresponding directory and queue entry
2. Every child's `parent` field matches the parent ID
3. Dependency references are valid (no dangling references)
4. No duplicate IDs in queue
5. Priority ordering is logical (children prioritized before parent)

Report summary to user.

## Output

```
Feature split completed!

Parent: {id} (module index, not directly developed)
├── {child1} [{size}] — {name}
├── {child2} [{size}] — {name}
├── {child3} [{size}] — {name}
└── {child4} [{size}] — {name}

Files created:
  features/pending-{child1}/spec.md, task.md
  features/pending-{child2}/spec.md, task.md
  ...

Files updated:
  features/pending-{parent}/spec.md  (-> module index)
  features/pending-{parent}/task.md  (-> progress tracker)
  feature-workflow/queue.yaml        (parent/children linked)

Queue: N sub-features added, downstream dependencies updated.
```

## Error Handling

| Error | Description | Solution |
|-------|-------------|----------|
| FEATURE_NOT_FOUND | Feature ID not in queue | Check ID spelling, use /list-features |
| FEATURE_ACTIVE | Feature is currently active | Complete or block before splitting |
| ALREADY_SPLIT | Feature already has children | Use /list-features to check status |
| QUEUE_PARSE_ERROR | queue.yaml malformed | Fix YAML syntax manually |
| ID_CONFLICT | Generated child ID already exists | Use different slug |
| PERMISSION_ERROR | Cannot write to features/ | Check filesystem permissions |

## Notes

1. **Business-first splitting** — split by business domain boundaries, not technical layers
2. **Parent as index** — original feature becomes a read-only module index
3. **Downstream deps stay on parent** — external features depend on the module, not individual children
4. **Children are independently actionable** — each can be started/completed independently
5. **Priority ordering** — children have higher priority than parent to ensure they complete first
