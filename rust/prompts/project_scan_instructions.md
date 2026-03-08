CRITICAL INSTRUCTIONS for project-wide SEARCH/REPLACE changes:
1. Process ALL TODOs using SEARCH/REPLACE format
2. Return changes in LOGICAL ORDER for developer review:
   - Group related changes together
   - Order by dependency (foundational changes first)
   - Consider the workflow a developer would follow
3. Each change MUST include:
   - "search": EXACT text to find (including the TODO line)
   - "replace": The new code to replace it with
   - "description": Brief description including file path
4. The "search" text must match EXACTLY including indentation
5. In your "explanation" field, provide reasoning for:
   - Why you ordered the changes this way
   - Any dependencies between changes
   - Which changes could be reviewed together

Example ordering rationale:
- Config/setup files first
- Core functionality before features
- Base classes before implementations
- Independent changes can be grouped
