# PDF Models - Claude Agent Skills

This directory contains custom Agent Skills for the pdf-models project. These skills provide Claude with specialized knowledge about the project's infrastructure, workflows, and common debugging patterns.

## Available Skills

### 1. aws-container-debugging
Debug AWS CodeBuild container builds, ECR image issues, and ECS task failures.

**Use when**:
- Container builds fail
- ECS tasks crash or won't start
- Permission errors in containers
- Out of memory errors
- Debugging deployment pipeline

**Key features**:
- Quick diagnostic commands
- Common error patterns with solutions
- Build and deployment verification workflows
- Python scripts for checking build status and task images

### 2. marker-pdf-integration
Configure and use the marker-pdf library for PDF to Markdown conversion.

**Use when**:
- Integrating Marker library
- Fixing Marker container issues
- Configuring Marker data directories
- Debugging Marker API changes
- Setting up model downloads

**Key features**:
- Directory structure requirements
- Environment variable configuration
- Model management and pre-downloading
- API version migration guide
- Common Marker-specific issues

### 3. aws-cdk-deployment
Deploy and manage AWS CDK stacks for the pdf-models project.

**Use when**:
- Deploying infrastructure
- Troubleshooting stack dependencies
- Fixing CDK synthesis issues
- Managing SSM parameters
- Understanding cross-stack references

**Key features**:
- Stack deployment order (critical for dependencies)
- SSM parameter reference
- Stack dependency graph
- Common deployment issues
- Best practices for CDK changes

### 4. aws-stepfunctions-debugging
Debug AWS Step Functions state machines and ECS task integration.

**Use when**:
- Job failures in Step Functions
- Step Functions errors
- ECS tasks not starting from Step Functions
- Execution tracking and tracing
- Understanding the dynamic task definition pattern

**Key features**:
- Execution flow analysis
- Common failure patterns
- Error code reference
- Python scripts for execution details
- Dynamic parameter resolution patterns

### 5. pdf-models-ci-cd
Complete CI/CD workflow for the pdf-models project.

**Use when**:
- Planning deployments
- Troubleshooting build pipelines
- Verifying changes are live
- Understanding the full workflow
- Setting up new environments

**Key features**:
- Complete workflows for all change types
- Build pipeline diagrams
- Verification checklists
- Testing strategies
- Deployment from scratch guide

## How Skills Work

Skills use **progressive disclosure** - Claude loads information in stages:

1. **Level 1 (Always loaded)**: Skill metadata (name, description)
2. **Level 2 (When triggered)**: Main SKILL.md instructions
3. **Level 3 (As needed)**: Reference files and scripts

This means you can have many skills installed without context penalty. Claude only loads what's needed for each task.

## Using Skills

Skills are automatically discovered and used by Claude when relevant to your request. You don't need to manually invoke them.

**Examples**:

- "The container build failed" → Claude uses `aws-container-debugging`
- "Deploy the MarkerStack" → Claude uses `aws-cdk-deployment`
- "Why did this job fail?" → Claude uses `aws-stepfunctions-debugging`

## Skill Structure

Each skill follows this structure:

```
skill-name/
├── SKILL.md              # Main instructions (loaded when triggered)
├── REFERENCE.md          # Additional reference (loaded as needed)
├── TROUBLESHOOTING.md    # Detailed troubleshooting (loaded as needed)
└── scripts/              # Executable scripts
    └── helper.py         # Script executed via bash, not loaded into context
```

## Scripts

Several skills include Python scripts for diagnostics:

**Container debugging**:
- `get_build_logs.py` - Fetch latest CodeBuild logs
- `check_task_image.py` - Verify which container image ECS is using
- `get_stopped_tasks.py` - Get stopped tasks and stop reasons

**Step Functions debugging**:
- `get_execution.py` - Detailed execution trace with all events
- `list_failed.py` - List recent failed executions

**Usage**:
```bash
python .claude/skills/aws-container-debugging/scripts/get_build_logs.py
python .claude/skills/aws-stepfunctions-debugging/scripts/get_execution.py <exec-name>
```

## Maintenance

As the project evolves, keep skills updated:

**When to update**:
- New infrastructure components added
- Build processes change
- Common errors shift
- New debugging patterns emerge

**What to update**:
- Error patterns in troubleshooting docs
- Script parameters (ARNs, names)
- Workflow steps if process changes
- SSM parameter references

## Skill Development Tips

Based on best practices from [Claude Skills documentation](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices):

1. **Be concise** - Assume Claude is smart, only add context Claude doesn't have
2. **Use progressive disclosure** - Keep SKILL.md focused, put details in separate files
3. **Provide scripts** - Pre-made scripts are more reliable than generated code
4. **Include examples** - Real error messages and solutions
5. **Test with real usage** - Iterate based on actual debugging sessions

## Contributing

When adding new skills:

1. Create directory: `.claude/skills/skill-name/`
2. Create `SKILL.md` with YAML frontmatter:
   ```yaml
   ---
   name: skill-name
   description: What it does and when to use it
   ---
   ```
3. Add reference files as needed
4. Make scripts executable: `chmod +x scripts/*.py`
5. Test with Claude to verify it triggers correctly

## References

- [Agent Skills Overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Agent Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Claude Code Skills Guide](https://code.claude.com/docs/en/skills)
