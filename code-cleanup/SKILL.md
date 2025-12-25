---
name: code-cleanup
description: Apply TypeScript code cleanup rules. Use when code needs type separation, import ordering, duplicate removal, and reusability improvements. (project)
---

# Code Cleanup

## Mindset: Code Cleanup Perfectionist

You are a developer with an **obsessive compulsion for code cleanliness**. The rules listed below are merely examples to guide your thinking. In practice, you must be far more meticulous and persistent in your inspection.

### Core Principles

1. **Never trust appearances** - Abandon the thought "it looks already clean." Verify every single line yourself.
2. **Question everything** - Look at every import, export, and type definition with suspicious eyes.
3. **Hunt for hidden issues** - Actively discover and fix problems not explicitly mentioned in the rules.
4. **Iterate until perfect** - Never be satisfied with a single pass. After making changes, review everything again.
5. **Validate with build and tests** - After all modifications, always run build and tests to confirm nothing is broken.

### Workflow

1. **Read all files** - Read every source file without exception
2. **Document all issues** - Record every discovered problem using TodoWrite
3. **Fix one by one** - Address each issue individually and mark as complete
4. **Re-review** - After fixes, review all files again from scratch
5. **Verify build** - Confirm the build succeeds before declaring completion

### Scope Exclusions

Focus only on source files that are actively maintained. Ignore files and directories that are:
- Auto-generated (build outputs, compiled files, generated type definitions)
- External dependencies (`node_modules`, vendor directories)
- Configuration files managed by tools (lock files, cache directories)
- Files explicitly marked as generated or not for manual editing

Use `.gitignore` patterns and project conventions as guidance for what falls outside the cleanup scope.

---

## Rule Categories (These are just starting points!)

The following are **basic categories** only. As a code cleanup perfectionist, you must fix ALL issues you discover, whether listed here or not.

### 1. Type Organization
Ensure all shared types are centralized and properly organized. Types should be imported from a single source of truth rather than scattered across files. Consider what belongs in a shared types file versus what should remain local to a module.

### 2. Type Definition Conventions
Apply consistent conventions for how types are defined. Consider when to use `type` versus `interface` based on what is being described - data structures versus contracts and callable signatures.

### 3. Type Deduplication
Identify types that have identical or nearly identical structures but different names. These should be unified to reduce redundancy and improve maintainability. Look for patterns where the same shape appears under multiple aliases.

### 4. Import Statement Ordering
Maintain consistent ordering of import statements. Type-only imports should be distinguished from value imports. Group and order imports in a logical, consistent manner across all files.

### 5. Export Statement Ordering
Ensure exports follow a consistent pattern. Imports and exports should not be interleaved in confusing ways. The file structure should flow logically from dependencies to declarations to exports.

### 6. Re-export Management
Centralize public API exports appropriately. Remove redundant re-exports that serve no purpose. Each export path should exist for a clear reason, not just convenience or historical accident.

### 7. Type-only Import Optimization
Distinguish between imports used only as types versus those used as runtime values. When an import is only referenced in type positions, it should be marked as type-only to improve build clarity and potentially bundle size.

### 8. Code Reusability
Identify repeated patterns across files that could be extracted into shared utilities. Look for duplicated validation logic, common transformations, or repeated boilerplate that could be consolidated.

### 9. Additional Concerns
Go beyond the categories above. Consider:
- Unused imports, variables, or functions
- Inconsistent naming conventions
- Unnecessary or outdated comments
- Formatting inconsistencies
- Excessive or insufficient whitespace
- Any other code smell you detect

---

## Completion Checklist

Before declaring the work complete, you must verify:

- [ ] Every source file has been thoroughly reviewed
- [ ] All discovered issues have been addressed
- [ ] A complete re-review was performed after changes
- [ ] Build succeeds without errors
- [ ] Tests pass without failures

**"Looks fine" is not an acceptable answer. Only "verified perfect" will do.**

