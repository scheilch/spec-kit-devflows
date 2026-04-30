# Bug Report: [TITLE]

**Bug ID**: [bugfix-###]
**Branch**: `bugfix/[###-short-description]`
**Created**: [DATE]
**Severity**: [ ] Critical | [ ] High | [ ] Medium | [ ] Low
**Component**: [file/module/feature affected]
**Status**: [ ] Investigating | [ ] Root Cause Found | [ ] Fixed | [ ] Verified

## Input
User description: "$ARGUMENTS"

## Current Behavior
[What actually happens - be specific with steps, error messages, unexpected output]
[NEEDS CLARIFICATION: Mark any details you cannot confirm from the codebase or user report]

## Expected Behavior
[What should happen according to spec or reasonable user expectations]
[NEEDS CLARIFICATION: If no spec exists, state the assumption and mark it for user review]

## Reproduction Steps
1. [Step 1 - be specific]
2. [Step 2 - include any required state/data]
3. [Step 3 - what action triggers the bug]
4. [Observe incorrect behavior]

**Frequency**: [ ] Always | [ ] Sometimes | [ ] Rare
**Environment**: [Browser/OS/Device if relevant, or N/A]

## Root Cause Analysis
*Filled during investigation (before running /speckit.plan)*

**Technical Explanation**:
[Why does this bug exist? What code/logic is wrong?]

**Files Involved**:
- [file1.ts: line XX - problem description]
- [file2.ts: line YY - problem description]

**Related Features**:
[Link to specs/###-feature if this bug affects a specific feature]

## Fix Strategy
*Filled during /speckit.plan (planning phase)*

**Approach**:
[High-level explanation of how to fix - 2-3 sentences]
[NEEDS CLARIFICATION: If multiple fix strategies exist, list alternatives and mark for user decision]

**Simplicity Check**:
- [ ] Fix is minimal — changes only what is necessary to resolve the bug
- [ ] No refactoring, feature additions, or "while we're here" improvements included
- [ ] If fix touches >3 files, justify why a simpler approach isn't possible

**Files to Modify**:
- [file1.ts - what changes needed]
- [file2.ts - what changes needed]

**Breaking Changes**: [ ] Yes | [ ] No
[If yes, explain impact and migration path]

## Rollback Plan

**How to Undo**:
```bash
git revert [commit-sha]
```

**Rollback Triggers** (revert if any occur within 24h):
- [ ] Existing tests break after fix
- [ ] New errors appear in production
- [ ] Fix causes performance regression
- [ ] Side effects in unrelated features

## Regression Test
*Created during /speckit.tasks and /speckit.implement (BEFORE applying fix)*

- [ ] Test written that reproduces bug (fails before fix)
- [ ] Test passes after fix applied
- [ ] Test added to test suite (not orphaned)
- [ ] Test covers edge cases identified during investigation

**Test File**: [path to regression test]
**Test Description**: [what the test validates]

## Verification Checklist
- [ ] Bug reproduced in clean environment
- [ ] Root cause identified and documented
- [ ] Fix implemented
- [ ] Regression test passes
- [ ] Existing tests still pass
- [ ] Manual verification complete
- [ ] Related documentation updated (if needed)

## Related Issues/Bugs
[Link to other bugs that might be related or caused by same root issue]

## Prevention
[How can we prevent this class of bug in the future? New validation? Better tests? Refactoring?]

---
*Bug report created using `/bugfix` workflow - See .specify/extensions/workflows/bugfix/*
