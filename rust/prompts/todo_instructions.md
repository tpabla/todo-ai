CRITICAL INSTRUCTIONS FOR SEARCH/REPLACE:
1. OPTIMIZE FOR LOGICAL BLOCKS: Combine related changes into larger, cohesive replacements
2. When multiple functions/sections work together, replace them as ONE logical unit
3. "search": Include ALL related code that forms a logical block (entire functions, classes, or sections)
4. "replace": The complete new implementation for the entire logical block
5. REDUCE DEVELOPER BURDEN: Use fewer, larger changes instead of many small ones
6. For related functions: Combine them in a single SEARCH/REPLACE if they're logically connected
7. For UI/display changes: Group all related UI elements in one change
8. INDENTATION: Copy EXACTLY from the search text
9. "description": Describe the logical transformation, not just mechanical changes
10. IMPORTANT: Think in terms of features/components, not individual functions

DIFF OPTIMIZATION GUIDELINES:
- Group related changes logically - what makes sense to review together?
- Include complete context - whole functions, not just individual lines
- Minimize review burden - aim for 2-3 cohesive diffs instead of 5-7 tiny ones
- For related functions (like recipe methods), group them in one diff
- Balance readability with completeness - not too small, not too massive
- Think like a reviewer - what would you want to approve as one unit?
