import os
from typing import Dict, Any, List, Optional
from .base import Provider
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
from response_parser import ResponseParser


class ClaudeProvider(Provider):
    """Claude API provider using Anthropic API"""

    def __init__(self):
        self.api_key = os.getenv('ANTHROPIC_API_KEY')
        self.anthropic = None
        self.name = 'anthropic'  # For parser hints
        self.parser = ResponseParser()

        # Initialize Anthropic client
        if self.api_key:
            try:
                import anthropic
                self.anthropic = anthropic.Anthropic(api_key=self.api_key)
            except ImportError:
                raise Exception(
                    "anthropic package not installed. Run: pip install anthropic")
        else:
            raise Exception(
                "ANTHROPIC_API_KEY environment variable not set")


    async def complete(
        self,
        instruction: str,
        context: str,
        model: str = 'claude-3-5-sonnet-20241022',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Generate completion using Claude"""
        prompt = self.build_prompt(instruction, context)

        if not self.anthropic:
            raise Exception("Claude API key not configured")

        try:
            response = self.anthropic.messages.create(
                model=model,
                max_tokens=max_tokens,
                temperature=temperature,
                messages=[
                    {"role": "user", "content": prompt}
                ]
            )

            content = response.content[0].text if response.content else ""
            return self.parse_response(content, provider_hint='anthropic')

        except Exception as e:
            raise Exception(f"Claude API error: {str(e)}")

    async def chat(
        self,
        messages: List[Dict[str, str]],
        model: str = 'claude-3-5-sonnet-20241022',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Handle chat with Claude"""
        if not self.anthropic:
            raise Exception("Claude API key not configured")

        # Convert messages to Claude format
        claude_messages = []
        for msg in messages:
            # Skip system messages or convert them to user messages with context
            if msg['role'] == 'system':
                claude_messages.append({
                    "role": "user",
                    "content": f"Context: {msg['content']}"
                })
            else:
                claude_messages.append({
                    "role": msg['role'] if msg['role'] != 'ai' else 'assistant',
                    "content": msg['content']
                })

        try:
            response = self.anthropic.messages.create(
                model=model,
                max_tokens=max_tokens,
                temperature=temperature,
                messages=claude_messages
            )

            content = response.content[0].text if response.content else ""

            # Check if response contains code
            parsed = self.parse_response(content, provider_hint='anthropic')
            if parsed.get('code'):
                return parsed
            else:
                return {"content": content}

        except Exception as e:
            raise Exception(f"Claude API error: {str(e)}")


    def get_available_models(self) -> List[str]:
        """Return list of available Claude models"""
        return [
            'claude-3-5-sonnet-20241022',  # Latest Sonnet 3.5
            'claude-3-5-haiku-20241022',   # Latest Haiku 3.5
            'claude-3-opus-20240229',      # Opus 3.0
            'claude-3-sonnet-20240229',    # Sonnet 3.0
            'claude-3-haiku-20240307',     # Haiku 3.0
        ]
