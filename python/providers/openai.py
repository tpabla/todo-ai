import os
from typing import Dict, Any, List
from .base import Provider


class OpenAIProvider(Provider):
    """OpenAI/GPT provider"""

    def __init__(self):
        self.api_key = os.getenv('OPENAI_API_KEY')
        self.client = None

        if self.api_key:
            try:
                from openai import AsyncOpenAI
                self.client = AsyncOpenAI(api_key=self.api_key)
            except ImportError:
                raise Exception("openai package not installed. Run: pip install openai")

    async def complete(
        self,
        instruction: str,
        context: str,
        model: str = 'gpt-4',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Generate completion using OpenAI"""
        if not self.client:
            raise Exception("OpenAI API key not configured")

        prompt = self.build_prompt(instruction, context)

        try:
            response = await self.client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": "You are a helpful coding assistant."},
                    {"role": "user", "content": prompt}
                ],
                temperature=temperature,
                max_tokens=max_tokens
            )

            content = response.choices[0].message.content if response.choices else ""
            return self.parse_response(content)

        except Exception as e:
            raise Exception(f"OpenAI API error: {str(e)}")

    async def chat(
        self,
        messages: List[Dict[str, str]],
        model: str = 'gpt-4',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Handle chat with OpenAI"""
        if not self.client:
            raise Exception("OpenAI API key not configured")

        try:
            response = await self.client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens
            )

            content = response.choices[0].message.content if response.choices else ""

            # Check if response contains code
            parsed = self.parse_response(content)
            if parsed.get('code'):
                return parsed
            else:
                return {"content": content}

        except Exception as e:
            raise Exception(f"OpenAI API error: {str(e)}")

    def get_available_models(self) -> List[str]:
        """Return list of available OpenAI models"""
        return [
            'gpt-4-turbo-preview',
            'gpt-4',
            'gpt-3.5-turbo',
            'gpt-3.5-turbo-16k'
        ]