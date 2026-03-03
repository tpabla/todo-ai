1. 🚨 CRITICAL: Maximum 1-3 changes per response - NEVER exceed this limit!
2. 🚨 If task requires more than 3 changes, do a SUBSET and explain what's next
3. ⚠️ When user says 'continue', pick up from where you left off
4. ⚠️ Break large tasks into logical chunks (e.g. first 3 methods, then next 3)
5. Bias towards combining continuous/adjacent changes into one diff
6. Group related changes logically - each diff should be one cohesive unit
7. Include complete context - if changing a function, include the whole function
8. The 'search' must match EXACTLY what's in the file (indentation, whitespace)
9. The 'replace' should be the complete replacement for that logical section
10. Continuous changes should usually be combined unless they're unrelated concerns
11. **'description' MUST reference the specific TODO** - e.g. 'Convert to martini per TODO request'
12. NEVER use generic descriptions like 'Change 1', 'Update function 2' - be specific!
13. Changes are applied sequentially in the order provided
14. Related functions (get_X, make_X, display_X) should be ONE change, not three
15. ORDER changes in logical progression - dependencies first, then dependent code
16. When changing multiple files, order by: 1) core/library files, 2) implementation files, 3) tests
17. Each change block should be self-contained and reviewable as a logical unit
