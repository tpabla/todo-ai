import aiohttp
import json
import os
from typing import Dict, Any, List
from .base import Provider


class OllamaProvider(Provider):
    """Ollama provider for local models"""

    def __init__(self):
        self.base_url = os.getenv('OLLAMA_HOST', 'http://localhost:11434')

    async def complete(
        self,
        instruction: str,
        context: str,
        model: str = 'llama3.2',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Generate completion using Ollama"""
        prompt = self.build_prompt(instruction, context)

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.base_url}/api/generate",
                json={
                    "model": model,
                    "prompt": prompt,
                    "temperature": temperature,
                    "num_predict": max_tokens,
                    "stream": False
                }
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    return self.parse_response(data.get('response', ''))
                else:
                    error_text = await response.text()
                    raise Exception(f"Ollama API error: {error_text}")

    async def chat(
        self,
        messages: List[Dict[str, str]],
        model: str = 'llama3.2',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Handle chat with Ollama"""
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.base_url}/api/chat",
                json={
                    "model": model,
                    "messages": messages,
                    "temperature": temperature,
                    "num_predict": max_tokens,
                    "stream": False
                }
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    content = data.get('message', {}).get('content', '')

                    # Check if response contains code
                    parsed = self.parse_response(content)
                    if parsed.get('code'):
                        return parsed
                    else:
                        return {"content": content}
                else:
                    error_text = await response.text()
                    raise Exception(f"Ollama API error: {error_text}")

    async def is_available(self) -> bool:
        """Check if Ollama is running and available"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.base_url}/api/tags") as response:
                    return response.status == 200
        except:
            return False

    async def list_models(self) -> List[str]:
        """List available models in Ollama"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.base_url}/api/tags") as response:
                    if response.status == 200:
                        data = await response.json()
                        return [model['name'] for model in data.get('models', [])]
        except:
            pass
        return []