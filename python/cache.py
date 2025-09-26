import json
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional


class CacheManager:
    """Manage .todoai cache directory"""

    def __init__(self):
        self.cache_dir_name = '.todoai'

    def get_cache_dir(self, project_root: str) -> Path:
        """Get or create cache directory"""
        cache_dir = Path(project_root) / self.cache_dir_name
        cache_dir.mkdir(exist_ok=True)

        # Create subdirectories
        (cache_dir / 'history').mkdir(exist_ok=True)
        (cache_dir / 'context').mkdir(exist_ok=True)

        return cache_dir

    async def save_context(self, project_root: str, context_data: Dict[str, Any]):
        """Save project context to cache"""
        cache_dir = self.get_cache_dir(project_root)
        context_file = cache_dir / 'context.json'

        # Add timestamp
        context_data['last_updated'] = datetime.now().isoformat()

        with open(context_file, 'w') as f:
            json.dump(context_data, f, indent=2)

    async def load_context(self, project_root: str) -> Optional[Dict[str, Any]]:
        """Load project context from cache"""
        cache_dir = Path(project_root) / self.cache_dir_name
        context_file = cache_dir / 'context.json'

        if context_file.exists():
            with open(context_file, 'r') as f:
                return json.load(f)

        return None

    async def save_interaction(
        self,
        file_path: str,
        instruction: str,
        result: Dict[str, Any],
        project_root: Optional[str] = None
    ):
        """Save interaction to history"""
        if not project_root:
            # Try to find project root
            current = Path(file_path).parent
            while current != current.parent:
                if (current / '.git').exists() or (current / self.cache_dir_name).exists():
                    project_root = str(current)
                    break
                current = current.parent

        if not project_root:
            return

        cache_dir = self.get_cache_dir(project_root)
        history_dir = cache_dir / 'history'

        # Create unique filename based on timestamp
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        history_file = history_dir / f"{timestamp}_{Path(file_path).stem}.json"

        interaction = {
            'timestamp': datetime.now().isoformat(),
            'file': file_path,
            'instruction': instruction,
            'result': result
        }

        with open(history_file, 'w') as f:
            json.dump(interaction, f, indent=2)

    async def get_recent_interactions(
        self,
        project_root: str,
        limit: int = 10
    ) -> list[Dict[str, Any]]:
        """Get recent interactions from history"""
        cache_dir = Path(project_root) / self.cache_dir_name
        history_dir = cache_dir / 'history'

        if not history_dir.exists():
            return []

        interactions = []
        history_files = sorted(history_dir.glob('*.json'), reverse=True)

        for file in history_files[:limit]:
            with open(file, 'r') as f:
                interactions.append(json.load(f))

        return interactions

    async def update_project_structure(self, project_root: str):
        """Scan and update project structure in cache"""
        project_path = Path(project_root)
        structure = {
            'directories': [],
            'files': {}
        }

        # Ignore patterns
        ignore_patterns = {
            '.git', '__pycache__', 'node_modules', '.venv', 'venv',
            'dist', 'build', '.pytest_cache', self.cache_dir_name
        }

        # Read .gitignore if exists
        gitignore_patterns = set()
        gitignore_file = project_path / '.gitignore'
        if gitignore_file.exists():
            with open(gitignore_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        gitignore_patterns.add(line.rstrip('/'))

        ignore_patterns.update(gitignore_patterns)

        # Walk project directory
        for root, dirs, files in os.walk(project_path):
            # Filter out ignored directories
            dirs[:] = [d for d in dirs if d not in ignore_patterns]

            rel_root = Path(root).relative_to(project_path)

            if str(rel_root) != '.':
                structure['directories'].append(str(rel_root))

            # Track files by extension
            for file in files:
                ext = Path(file).suffix
                if ext not in structure['files']:
                    structure['files'][ext] = []

                file_path = rel_root / file if str(rel_root) != '.' else Path(file)
                structure['files'][ext].append(str(file_path))

        # Save structure to context
        context = await self.load_context(project_root) or {}
        context['project_structure'] = structure
        await self.save_context(project_root, context)

        return structure

    def get_config(self, project_root: str) -> Optional[Dict[str, Any]]:
        """Load project-specific configuration"""
        config_file = Path(project_root) / self.cache_dir_name / 'config.json'

        if config_file.exists():
            with open(config_file, 'r') as f:
                return json.load(f)

        return None

    def save_config(self, project_root: str, config: Dict[str, Any]):
        """Save project-specific configuration"""
        cache_dir = self.get_cache_dir(project_root)
        config_file = cache_dir / 'config.json'

        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)