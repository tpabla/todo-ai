import os
import re
from pathlib import Path
from typing import List, Dict, Any, Optional
import ast
import json


class ContextBuilder:
    """Build context for LLM from project files"""

    def __init__(self):
        self.import_patterns = {
            'python': r'(?:from\s+(\S+)\s+)?import\s+(.+)',
            'javascript': r'(?:import|require)\s*\(?\s*[\'"]([^\'"]+)[\'"]\)?',
            'typescript': r'(?:import|require)\s*(?:\{[^}]*\}\s*from\s*)?[\'"]([^\'"]+)[\'"]',
            'go': r'import\s+(?:\w+\s+)?"([^"]+)"',
            'rust': r'use\s+([\w:]+)',
            'java': r'import\s+([\w.]+);',
            'cpp': r'#include\s*[<"]([^>"]+)[>"]'
        }

    async def build(
        self,
        file_path: str,
        file_content: str,
        instruction: str,
        language: str = 'python',
        surrounding_lines: List[Dict] = None,
        project_root: str = None,
        cached_context: Dict = None,
        other_buffers: List[Dict] = None
    ) -> str:
        """Build comprehensive context for the LLM"""
        context_parts = []

        # 1. File information
        context_parts.append(f"File: {file_path}")
        context_parts.append(f"Language: {language}")
        context_parts.append("")

        # 2. Instruction
        context_parts.append(f"Task: {instruction}")
        context_parts.append("")

        # 3. Surrounding code context
        if surrounding_lines:
            context_parts.append("Code context:")
            context_parts.append("```" + language)
            for line_info in surrounding_lines:
                prefix = ">>> " if line_info.get('is_target') else "    "
                context_parts.append(f"{prefix}{line_info['content']}")
            context_parts.append("```")
            context_parts.append("")

        # 4. Imports and dependencies
        imports = self.extract_imports(file_content, language)
        if imports:
            context_parts.append("File imports/dependencies:")
            for imp in imports:
                context_parts.append(f"  - {imp}")
            context_parts.append("")

        # 5. Related files from imports
        if project_root and imports:
            related_files = await self.find_related_files(imports, project_root, language)
            if related_files:
                context_parts.append("Related files found:")
                for file in related_files[:5]:  # Limit to 5 files
                    context_parts.append(f"  - {file}")
                context_parts.append("")

        # 6. Project structure (from cache if available)
        if cached_context and cached_context.get('project_structure'):
            context_parts.append("Project structure:")
            context_parts.append(json.dumps(cached_context['project_structure'], indent=2))
            context_parts.append("")

        # 7. Full file content (if small enough)
        if len(file_content) < 5000:  # Only include if under 5000 chars
            context_parts.append("Full file content:")
            context_parts.append("```" + language)
            context_parts.append(file_content)
            context_parts.append("```")
            context_parts.append("")

        # 8. Other open buffers (for context only)
        if other_buffers:
            context_parts.append("Other open files (read-only context):")
            for buf in other_buffers[:3]:  # Limit to 3 files
                context_parts.append(f"\n=== {buf['filename']} ===")
                context_parts.append(f"```{buf.get('filetype', '')}")
                # Show first 50 lines only
                content = buf['content']
                lines = content.split('\n')[:50]
                context_parts.append('\n'.join(lines))
                if len(content.split('\n')) > 50:
                    context_parts.append("... (truncated)")
                context_parts.append("```")
            context_parts.append("")
            context_parts.append("NOTE: You can only edit the current file, not these other files.")
            context_parts.append("")

        # 9. Language-specific context
        lang_context = self.get_language_context(file_content, language)
        if lang_context:
            context_parts.append("Code structure:")
            for key, value in lang_context.items():
                if value:
                    context_parts.append(f"  {key}: {', '.join(value) if isinstance(value, list) else value}")
            context_parts.append("")

        return "\n".join(context_parts)

    def extract_imports(self, content: str, language: str) -> List[str]:
        """Extract imports/includes from file content"""
        pattern = self.import_patterns.get(language)
        if not pattern:
            return []

        imports = []
        for line in content.split('\n'):
            match = re.search(pattern, line)
            if match:
                imports.append(match.group(0))

        return imports

    async def find_related_files(
        self,
        imports: List[str],
        project_root: str,
        language: str
    ) -> List[str]:
        """Find related files based on imports"""
        related = []
        root_path = Path(project_root)

        for imp in imports[:10]:  # Limit to first 10 imports
            # Extract module/file name
            module_name = self.extract_module_name(imp, language)
            if not module_name:
                continue

            # Convert module name to potential file paths
            potential_paths = self.module_to_paths(module_name, language)

            # Search for files
            for path in potential_paths:
                full_path = root_path / path
                if full_path.exists():
                    related.append(str(full_path.relative_to(root_path)))
                    break

        return related

    def extract_module_name(self, import_stmt: str, language: str) -> Optional[str]:
        """Extract module name from import statement"""
        if language == 'python':
            match = re.search(r'from\s+(\S+)|import\s+(\S+)', import_stmt)
            if match:
                return match.group(1) or match.group(2).split(',')[0].strip()

        elif language in ['javascript', 'typescript']:
            match = re.search(r'[\'"]([^\'"]+)[\'"]', import_stmt)
            if match:
                return match.group(1)

        elif language == 'go':
            match = re.search(r'"([^"]+)"', import_stmt)
            if match:
                return match.group(1)

        return None

    def module_to_paths(self, module: str, language: str) -> List[str]:
        """Convert module name to potential file paths"""
        paths = []

        if language == 'python':
            # Replace dots with slashes
            base = module.replace('.', '/')
            paths.extend([
                f"{base}.py",
                f"{base}/__init__.py",
                f"{base}/main.py"
            ])

        elif language in ['javascript', 'typescript']:
            # Handle relative and absolute paths
            if module.startswith('.'):
                base = module
            else:
                base = f"node_modules/{module}"

            paths.extend([
                f"{base}.js",
                f"{base}.ts",
                f"{base}/index.js",
                f"{base}/index.ts",
                f"{base}.jsx",
                f"{base}.tsx"
            ])

        elif language == 'go':
            # Go modules
            paths.append(f"{module}/{Path(module).name}.go")

        return paths

    def get_language_context(self, content: str, language: str) -> Dict[str, Any]:
        """Extract language-specific context"""
        context = {}

        if language == 'python':
            try:
                tree = ast.parse(content)
                context['classes'] = [node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)]
                context['functions'] = [node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]
            except:
                pass

        elif language in ['javascript', 'typescript']:
            # Simple regex-based extraction
            context['functions'] = re.findall(r'function\s+(\w+)', content)
            context['classes'] = re.findall(r'class\s+(\w+)', content)
            context['exports'] = re.findall(r'export\s+(?:default\s+)?(\w+)', content)

        elif language == 'go':
            context['functions'] = re.findall(r'func\s+(?:\([^)]+\)\s+)?(\w+)', content)
            context['types'] = re.findall(r'type\s+(\w+)', content)

        return context