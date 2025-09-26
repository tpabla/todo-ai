import aiohttp
import os
from typing import Dict, Any, List, Optional
from .base import Provider


class CustomProvider(Provider):
    """Custom endpoint provider for OpenAI-compatible APIs"""

    def __init__(self):
        self.base_url = os.getenv('CUSTOM_LLM_ENDPOINT', 'http://localhost:8080')
        self.api_key = os.getenv('CUSTOM_LLM_API_KEY', '')
        self.custom_headers = {}

        # Parse any custom headers from environment
        for key, value in os.environ.items():
            if key.startswith('CUSTOM_LLM_HEADER_'):
                header_name = key.replace('CUSTOM_LLM_HEADER_', '').replace('_', '-')
                self.custom_headers[header_name] = value

    async def complete(
        self,
        instruction: str,
        context: str,
        model: str = 'default',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Generate completion using custom endpoint"""
        prompt = self.build_prompt(instruction, context)

        headers = {
            'Content-Type': 'application/json',
            **self.custom_headers
        }

        if self.api_key:
            headers['Authorization'] = f'Bearer {self.api_key}'

        # Try OpenAI-compatible format first
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": "You are a helpful coding assistant."},
                {"role": "user", "content": prompt}
            ],
            "temperature": temperature,
            "max_tokens": max_tokens
        }

        async with aiohttp.ClientSession() as session:
            # Try /v1/chat/completions endpoint (OpenAI compatible)
            try:
                async with session.post(
                    f"{self.base_url}/v1/chat/completions",
                    json=payload,
                    headers=headers
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        content = data['choices'][0]['message']['content']
                        return self.parse_response(content)
            except:
                pass

            # Try /completions endpoint (simple format)
            try:
                async with session.post(
                    f"{self.base_url}/completions",
                    json={
                        "prompt": prompt,
                        "model": model,
                        "temperature": temperature,
                        "max_tokens": max_tokens
                    },
                    headers=headers
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        content = data.get('text', data.get('response', ''))
                        return self.parse_response(content)
            except:
                pass

            # Try raw prompt endpoint
            try:
                async with session.post(
                    self.base_url,
                    json={"prompt": prompt},
                    headers=headers
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        content = data.get('response', data.get('text', str(data)))
                        return self.parse_response(content)
            except Exception as e:
                raise Exception(f"Custom endpoint error: {str(e)}")

        raise Exception("Failed to connect to custom endpoint")

    async def chat(
        self,
        messages: List[Dict[str, str]],
        model: str = 'default',
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """Handle chat with custom endpoint"""
        headers = {
            'Content-Type': 'application/json',
            **self.custom_headers
        }

        if self.api_key:
            headers['Authorization'] = f'Bearer {self.api_key}'

        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens
        }

        async with aiohttp.ClientSession() as session:
            # Try OpenAI-compatible format
            try:
                async with session.post(
                    f"{self.base_url}/v1/chat/completions",
                    json=payload,
                    headers=headers
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        content = data['choices'][0]['message']['content']

                        parsed = self.parse_response(content)
                        if parsed.get('code'):
                            return parsed
                        else:
                            return {"content": content}
            except:
                pass

            # Try simple chat endpoint
            try:
                async with session.post(
                    f"{self.base_url}/chat",
                    json={"messages": messages},
                    headers=headers
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        content = data.get('response', data.get('text', str(data)))
                        return {"content": content}
            except Exception as e:
                raise Exception(f"Custom endpoint error: {str(e)}")

        raise Exception("Failed to connect to custom endpoint")

    def configure(self, endpoint: str, api_key: Optional[str] = None, headers: Optional[Dict] = None):
        """Configure custom endpoint at runtime"""
        self.base_url = endpoint
        if api_key:
            self.api_key = api_key
        if headers:
            self.custom_headers.update(headers)