---
description: 'Initialize a project with the feature-workflow system. Creates config files, directories, and project context.'
---

# Skill: init-project

Initialize the feature-workflow system in the current project. Creates all necessary configuration files, directory structures, and project context.

## Usage

```
/init-project                          # Interactive mode (guided setup)
/init-project --quick                  # Quick mode (minimal prompts, smart defaults)
/init-project --name=MyProject         # Specify project name
/init-project --tech=python-311        # Specify tech stack
/init-project --check                  # Check initialization status only
```

## Pre-flight Checks

### Check 1: Git Repository

Verify current directory is a Git repository:
```bash
git rev-parse --is-inside-work-tree
```

If not a Git repo: Offer to `git init`.

### Check 2: Already Initialized

Check if `feature-workflow/config.yaml` already exists:
- If exists: Ask whether to **reinitialize** (backup old config first) or **abort**
- If not: Proceed with initialization

### Check 3: Main Branch

Detect the main branch:
```bash
git remote show origin | grep 'HEAD branch' || echo "main"
git branch -a | grep -E 'main|master'
```

Default: `main`. Ask user to confirm or specify.

## Interactive Setup (Default Mode)

### Step 1: Collect Project Information

Ask the following (provide smart defaults based on directory analysis):

| Field | Source | Default |
|-------|--------|---------|
| **Project Name** | Directory name (PascalCase) | `basename $(pwd)` |
| **Tech Stack** | Scan for config files | See detection below |
| **Test Framework** | Scan for test configs | See detection below |
| **Worktree Prefix** | Project name | Same as project name |
| **Max Concurrent** | Ask | 3 |
| **Main Branch** | Git detection | main |

**Tech Stack Detection:**

```
1. Check for files:
   - requirements.txt / pyproject.toml → python (version from python --version)
   - package.json → node (version from node --version)
   - go.mod → go
   - Cargo.toml → rust
   - pom.xml → java-maven
   - build.gradle → java-gradle

2. Check for frameworks:
   - Django: settings.py, manage.py → python-django
   - FastAPI: app/main.py → python-fastapi
   - Next.js: next.config.* → node-nextjs
   - React: src/App.*x → node-react
   - Vue: vue.config.* → node-vue

3. Result format: {language}-{version} or {language}-{framework}
   Examples: python-311, node-20, python-fastapi, node-nextjs
```

**Test Framework Detection:**

```
1. pytest: conftest.py, pytest.ini, [tool.pytest.ini_options]
2. jest: jest.config.*, "jest" in package.json
3. vitest: vitest.config.*
4. unittest: tests/ dir with test_*.py files
5. Go testing: *_test.go files
6. Default: pytest (python) / jest (node)
```

### Step 2: Confirm Configuration

Display the detected/collected configuration and ask for confirmation:

```
Project Initialization Preview
------------------------------
Name:       MyProject
Tech:       python-311
Test:       pytest
Main Branch: main
Worktree:   ../MyProject-feat-xxx
Parallel:   3

Files to create:
  ✓ feature-workflow/config.yaml
  ✓ feature-workflow/queue.yaml
  ✓ features/
  ✓ features/archive/
  ✓ features/archive/archive-log.yaml
  ✓ project-context.md
  ✓ .claude/ (if not exists)

Continue? (y/n/edit)
```

### Step 3: Create Directory Structure

```bash
# Feature workflow directory
mkdir -p feature-workflow

# Features directory
mkdir -p features/archive

# Ensure .claude directory exists
mkdir -p .claude/commands
mkdir -p .claude/agents
mkdir -p .claude/skills
```

### Step 4: Generate Configuration Files

#### 4.1 config.yaml

Generate from template, replacing placeholders:

```yaml
# feature-workflow/config.yaml
project:
  name: {PROJECT_NAME}
  main_branch: {MAIN_BRANCH}
  repo_path: .
  tech_stack: {TECH_STACK}
  test_framework: {TEST_FRAMEWORK}

parallelism:
  max_concurrent: {MAX_CONCURRENT}

git:
  remote: origin
  auto_push: false
  merge_strategy: "--no-ff"
  push_tags: true

branch_prefix: feature
worktree_prefix: {WORKTREE_PREFIX}
worktree_base: ..

workflow:
  auto_start: false
  auto_start_next: true
  require_checklist: true
  splitting:
    enabled: true
    threshold: 3
  testing:
    pytest_enabled: {PYTEST_ENABLED}
    test_dir: {TEST_DIR}
    coverage_enabled: true
    coverage_target: 80

completion:
  archive:
    create_tag: true
    tag_format: "{id}-{date}"
    tag_date_format: "%Y%m%d"
  cleanup:
    delete_worktree: true
    delete_branch: true
  record:
    update_spec: true
    update_archive_log: true

naming:
  feature_prefix: feat
  branch_prefix: feature
  worktree_prefix: {WORKTREE_PREFIX}

paths:
  features_dir: features
  archive_dir: features/archive
  worktree_base: ..
  repo_path: .
```

#### 4.2 queue.yaml

```yaml
# feature-workflow/queue.yaml
meta:
  last_updated: "{ISO_TIMESTAMP}"
  version: 1

parents: []
active: []
pending: []
blocked: []
completed: []
```

#### 4.3 archive-log.yaml

```yaml
# features/archive/archive-log.yaml
meta:
  last_updated: "{ISO_TIMESTAMP}"
  version: 1
  total_completed: 0

records: []
```

### Step 5: Generate Project Context

Run quick project analysis to populate `project-context.md`:

1. **Scan project structure** - List main directories
2. **Detect dependencies** - Read package.json / requirements.txt / pyproject.toml
3. **Identify frameworks** - Check config files
4. **Find code patterns** - Scan a few representative files for naming conventions
5. **Generate project-context.md** from template

The generated `project-context.md` should include:
- Technology stack table
- Directory structure
- Initial code patterns (naming, imports)
- Empty sections for critical rules, anti-patterns, recent changes

**If unable to detect patterns** (empty project): Generate minimal template with placeholders.

### Step 6: Copy Skills to Project

If this is being run from the marketplace (not from an already-installed project):

```bash
# Copy plugin files to .claude/ directory
# Commands
cp {marketplace_path}/commands/dev-agent.md .claude/commands/

# Agents
cp {marketplace_path}/agents/dev-subagent.md .claude/agents/

# Skills (all .md files)
cp {marketplace_path}/skills/*.md .claude/skills/

# Templates (to feature-workflow/templates/)
mkdir -p feature-workflow/templates
cp {marketplace_path}/templates/*.md feature-workflow/templates/
```

**If skills already exist** in `.claude/`: Ask whether to overwrite or skip.

### Step 7: Git Add

Add the workflow files to Git (do NOT commit automatically):

```bash
git add feature-workflow/
git add features/
git add project-context.md
```

## Quick Mode (`--quick`)

Skip all prompts, use detected defaults:
- Project name: directory name
- Tech stack: auto-detected
- Test framework: auto-detected
- Main branch: auto-detected
- Max concurrent: 3

Create all files directly. Only prompt if detection fails completely.

## Check Mode (`--check`)

Verify initialization status:

```
Feature Workflow Status
-----------------------
✓ feature-workflow/config.yaml     (exists)
✓ feature-workflow/queue.yaml      (exists)
✓ features/                         (exists)
✓ features/archive/                 (exists)
✓ features/archive/archive-log.yaml (exists)
✓ project-context.md               (exists)
✓ .claude/commands/dev-agent.md    (exists)
✓ .claude/agents/dev-subagent.md   (exists)
✓ .claude/skills/                  (10 files)

Missing:
  ✗ .claude/skills/init-project.md

Run /init-project to fix.
```

## Output

### Success

```
Feature Workflow initialized!

Project:    MyProject
Tech Stack: python-311
Test:       pytest
Branch:     main
Parallel:   3

Created:
  feature-workflow/config.yaml       # Main configuration
  feature-workflow/queue.yaml        # Feature queue
  features/                          # Feature directories
  features/archive/archive-log.yaml  # Archive log
  project-context.md                 # Project context
  .claude/commands/dev-agent.md      # Dev agent command
  .claude/agents/dev-subagent.md     # Dev subagent
  .claude/skills/*.md                # 12 skills

Next steps:
  1. Review feature-workflow/config.yaml
  2. Run /pm-agent to build full project context
  3. Run /new-feature to create your first feature
```

### Reinitialize

```
Feature Workflow already initialized!
Backup saved to: feature-workflow/config.yaml.bak

Reinitializing with new settings...
```

## Error Handling

| Error | Description | Solution |
|-------|-------------|----------|
| NOT_GIT_REPO | Not a Git repository | Run git init first |
| ALREADY_INITIALIZED | Config already exists | Use --force or confirm reinit |
| PERMISSION_ERROR | Cannot create directories | Check filesystem permissions |
| DETECTION_FAILED | Cannot detect tech stack | Use --tech= to specify manually |
| TEMPLATE_ERROR | Template processing failed | Check template files |

## Notes

1. **Non-destructive** - Never overwrites without confirmation
2. **Backup first** - Always backup existing config before reinit
3. **Smart defaults** - Leverage project analysis for sensible defaults
4. **Incremental** - Can be run multiple times, only creates missing files
5. **Marketplace-aware** - Detects if running from marketplace and copies plugin files
