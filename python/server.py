#!/usr/bin/env python3
import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Optional, Dict, Any
import logging

from aiohttp import web
import aiohttp_cors

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from providers.base import Provider
from providers.ollama import OllamaProvider
from providers.claude import ClaudeProvider
from providers.openai import OpenAIProvider
from providers.custom import CustomProvider
from context import ContextBuilder
from cache import CacheManager

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class TodoAIServer:
    def __init__(self, host='localhost', port=8765):
        self.host = host
        self.port = port
        self.app = web.Application()
        self.providers: Dict[str, Provider] = {}
        self.context_builder = ContextBuilder()
        self.cache_manager = CacheManager()

        self._setup_providers()
        self._setup_routes()
        self._setup_cors()

    def _setup_providers(self):
        """Initialize available providers"""
        self.providers = {
            'ollama': OllamaProvider(),
            'claude': ClaudeProvider(),
            'openai': OpenAIProvider(),
            'custom': CustomProvider()
        }

    def _setup_routes(self):
        """Set up HTTP routes"""
        self.app.router.add_get('/health', self.health_check)
        self.app.router.add_post('/api/completion', self.handle_completion)
        self.app.router.add_post('/api/chat', self.handle_chat)
        self.app.router.add_post('/api/context/update', self.update_context)
        self.app.router.add_get('/api/context', self.get_context)

    def _setup_cors(self):
        """Setup CORS for local development"""
        cors = aiohttp_cors.setup(self.app, defaults={
            "*": aiohttp_cors.ResourceOptions(
                allow_credentials=True,
                expose_headers="*",
                allow_headers="*",
                allow_methods="*"
            )
        })

        for route in list(self.app.router.routes()):
            cors.add(route)

    async def health_check(self, request):
        """Health check endpoint"""
        return web.json_response({'status': 'ok'})

    async def handle_completion(self, request):
        """Handle completion requests"""
        try:
            data = await request.json()
            request_id = data.get('id')
            params = data.get('params', {})

            # Get provider and model
            provider_name = params.get('provider', 'ollama')
            model = params.get('model', 'llama3.2')

            # Get provider instance
            provider = self.providers.get(provider_name)
            if not provider:
                return web.json_response({
                    'id': request_id,
                    'error': f'Unknown provider: {provider_name}'
                })

            # Build context
            context = await self.context_builder.build(
                file_path=params.get('file_path'),
                file_content=params.get('context', {}).get('file_content', ''),
                instruction=params.get('instruction'),
                language=params.get('context', {}).get('language', 'python'),
                surrounding_lines=params.get('context', {}).get('surrounding_lines', []),
                project_root=params.get('context', {}).get('project_root'),
                cached_context=params.get('context', {}).get('cached_context'),
                other_buffers=params.get('context', {}).get('other_buffers', [])
            )

            # Generate completion
            result = await provider.complete(
                instruction=params.get('instruction'),
                context=context,
                model=model,
                temperature=params.get('temperature', 0.7),
                max_tokens=params.get('max_tokens', 4096)
            )

            # Cache the result
            if params.get('file_path'):
                await self.cache_manager.save_interaction(
                    file_path=params.get('file_path'),
                    instruction=params.get('instruction'),
                    result=result
                )

            return web.json_response({
                'id': request_id,
                'result': result
            })

        except Exception as e:
            logger.error(f"Error in completion: {e}")
            return web.json_response({
                'id': data.get('id'),
                'error': str(e)
            })

    async def handle_chat(self, request):
        """Handle chat messages"""
        try:
            data = await request.json()
            request_id = data.get('id')
            params = data.get('params', {})

            # Get provider from context or config
            provider_name = params.get('provider', 'ollama')
            model = params.get('model', 'llama3.2')

            provider = self.providers.get(provider_name)
            if not provider:
                return web.json_response({
                    'id': request_id,
                    'error': f'Unknown provider: {provider_name}'
                })

            # Build chat context
            messages = params.get('history', [])
            messages.append({
                'role': 'user',
                'content': params.get('message', '')
            })

            # Add current context if provided
            if params.get('context'):
                system_message = self._build_chat_context(params['context'])
                messages.insert(0, {
                    'role': 'system',
                    'content': system_message
                })

            # Get chat response
            result = await provider.chat(
                messages=messages,
                model=model,
                temperature=params.get('temperature', 0.7),
                max_tokens=params.get('max_tokens', 4096)
            )

            return web.json_response({
                'id': request_id,
                'result': result
            })

        except Exception as e:
            logger.error(f"Error in chat: {e}")
            return web.json_response({
                'id': data.get('id'),
                'error': str(e)
            })

    def _build_chat_context(self, context):
        """Build system message from context"""
        todo = context.get('todo', {})
        pending_diff = context.get('pending_diff', {})
        open_buffers = context.get('open_buffers', [])
        current_buffer = context.get('current_buffer')

        system_msg = "You are an AI coding assistant with access to the user's open files in Neovim.\n\n"

        # Add open buffers context
        if open_buffers:
            system_msg += "Open Files:\n"
            for buffer in open_buffers:
                is_current = buffer['id'] == current_buffer
                status = " [CURRENT]" if is_current else ""
                modified = " [MODIFIED]" if buffer.get('modified') else ""
                system_msg += f"- {buffer['filename']} (Buffer #{buffer['id']}{status}{modified})\n"
            system_msg += "\n"

            # Add file contents for context (limited)
            system_msg += "File Contents (first 100 lines):\n"
            for buffer in open_buffers[:3]:  # Limit to first 3 files for context
                system_msg += f"\n=== {buffer['filename']} ===\n"
                system_msg += f"```{buffer.get('filetype', '')}\n"
                system_msg += buffer['content'][:2000]  # Limit content size
                if len(buffer['content']) > 2000:
                    system_msg += "\n... (truncated)"
                system_msg += "\n```\n"

        if todo:
            system_msg += f"\nCurrent TODO: {todo.get('instruction', '')}\n"
            system_msg += f"Line: {todo.get('line', '')}\n\n"

        if pending_diff:
            system_msg += "Current proposed change:\n"
            system_msg += f"```\n{pending_diff.get('code', '')}\n```\n\n"

        system_msg += """You can:
1. Answer questions about the code
2. Suggest edits to any open file
3. Help refine implementations
4. Provide code explanations

When suggesting edits, specify the buffer ID and line numbers.
Format edits as: EDIT[buffer_id:line_start-line_end]: <new_content>"""

        return system_msg

    async def update_context(self, request):
        """Update cached context"""
        try:
            data = await request.json()
            project_root = data.get('project_root')
            context_data = data.get('context')

            if project_root and context_data:
                await self.cache_manager.save_context(project_root, context_data)
                return web.json_response({'status': 'ok'})

            return web.json_response({'error': 'Missing data'})

        except Exception as e:
            logger.error(f"Error updating context: {e}")
            return web.json_response({'error': str(e)})

    async def get_context(self, request):
        """Get cached context"""
        try:
            project_root = request.query.get('project_root')

            if project_root:
                context = await self.cache_manager.load_context(project_root)
                return web.json_response({'context': context})

            return web.json_response({'error': 'Missing project_root'})

        except Exception as e:
            logger.error(f"Error getting context: {e}")
            return web.json_response({'error': str(e)})

    def run(self):
        """Run the server"""
        logger.info(f"Starting Todo-AI server on {self.host}:{self.port}")
        web.run_app(self.app, host=self.host, port=self.port)


def main():
    """Main entry point"""
    # Get config from environment or defaults
    host = os.getenv('TODOAI_HOST', 'localhost')
    port = int(os.getenv('TODOAI_PORT', 8765))

    server = TodoAIServer(host, port)
    server.run()


if __name__ == '__main__':
    main()