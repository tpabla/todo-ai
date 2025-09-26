from abc import ABC, abstractmethod
from typing import Dict, Any, List, Optional
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
from response_parser import ResponseParser


class Provider(ABC):
    """Abstract base class for LLM providers"""

    @abstractmethod
    async def complete(
        self,
        instruction: str,
        context: str,
        model: str,
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Generate code completion for the given instruction

        Returns:
            Dict with 'code' and 'explanation' keys
        """
        pass

    @abstractmethod
    async def chat(
        self,
        messages: List[Dict[str, str]],
        model: str,
        temperature: float = 0.7,
        max_tokens: int = 4096,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Handle chat conversation

        Returns:
            Dict with 'content' and optional 'code' keys
        """
        pass

    def build_prompt(self, instruction: str, context: str) -> str:
        """Build a prompt from instruction and context"""
        return f"""You are a helpful coding assistant. Complete the following task.

Task: {instruction}

Context:
{context}

Provide ONLY the code implementation to replace the TODO comment. Do not include any explanations, comments, or markdown formatting. Just the raw code.

Example response for "write a hello world function":
def hello_world():
    print("Hello, world!")

Now provide the code for the task above:"""

    def parse_response(self, response: str, provider_hint: Optional[str] = None) -> Dict[str, Any]:
        """Parse response from model using enhanced parser"""
        # Try to use the enhanced parser first
        try:
            result = self.parser.parse(response, hint=provider_hint or self.name)

            # Ensure we have the required fields
            if 'code' not in result and 'parsed_sections' in result:
                # Try to extract code from parsed sections
                for key in ['code', 'implementation', 'solution']:
                    if key in result['parsed_sections']:
                        result['code'] = result['parsed_sections'][key]
                        break

            # Always include raw response
            if 'raw_response' not in result:
                result['raw_response'] = response

            # Format thinking content if present
            if result.get('thinking'):
                result['thinking_formatted'] = self._format_thinking(result['thinking'])

            return result

        except Exception as e:
            # Fallback to simple parsing if enhanced parser fails
            import json
            import re

            # Store the original response
            original_response = response

            # Clean up the response first
            response = response.strip()

            # Remove thinking tags if present
            response = re.sub(r'<think>.*?</think>', '', response, flags=re.DOTALL).strip()

            result = {}

            # First check if it looks like plain code (our new prompt format)
            if response and not response.startswith('{'):
                # It's likely plain code, return as-is
                result = {
                    "code": response,
                    "explanation": "Generated code",
                    "raw_response": original_response
                }
                return result

            # Try to parse as JSON
            try:
                # First attempt: direct JSON parse
                parsed = json.loads(response)
                if isinstance(parsed, dict) and 'code' in parsed:
                    parsed['raw_response'] = original_response
                    return parsed
            except:
                # Try to extract JSON from mixed content
                json_match = re.search(r'\{.*"code".*\}', response, re.DOTALL)
                if json_match:
                    try:
                        json_str = json_match.group()
                        # Clean up common issues
                        json_str = re.sub(r'"""', '"', json_str)
                        parsed = json.loads(json_str)
                        if isinstance(parsed, dict) and 'code' in parsed:
                            parsed['raw_response'] = original_response
                            return parsed
                    except:
                        pass

            # Fallback: try to extract code blocks
            if "```" in response:
                code_blocks = re.findall(r'```(?:\w+)?\n(.*?)\n```', response, re.DOTALL)
                if code_blocks:
                    return {
                        "code": code_blocks[0],
                        "explanation": "Extracted from code block",
                        "raw_response": original_response
                    }

            # Last resort: return the whole response as code
            return {
                "code": response,
                "explanation": "",
                "raw_response": original_response
            }

    def _format_thinking(self, thinking_sections: Dict[str, str]) -> str:
        """Format thinking sections as markdown"""
        formatted = []

        # Create a nice markdown representation of thinking
        formatted.append("## 🧠 AI Thinking Process\n")

        # Map tag types to nice headers and emojis
        tag_display = {
            'thinking': ('💭 Thinking', thinking_sections.get('thinking')),
            'thought': ('💡 Thoughts', thinking_sections.get('thought')),
            'reasoning': ('🔍 Reasoning', thinking_sections.get('reasoning')),
            'analysis': ('📊 Analysis', thinking_sections.get('analysis')),
            'planning': ('📋 Planning', thinking_sections.get('planning')),
            'approach': ('🎯 Approach', thinking_sections.get('approach')),
            'strategy': ('♟️ Strategy', thinking_sections.get('strategy')),
            'scratch': ('📝 Scratch Work', thinking_sections.get('scratch')),
            'work': ('⚙️ Work', thinking_sections.get('work')),
            'internal': ('🔒 Internal Process', thinking_sections.get('internal')),
        }

        for tag_type, (header, content) in tag_display.items():
            if content:
                formatted.append(f"### {header}\n")

                # Format the content nicely
                lines = content.split('\n')
                for line in lines:
                    line = line.strip()
                    if line:
                        # Check if it's a list item
                        if line.startswith('- ') or line.startswith('* ') or line.startswith('+ '):
                            formatted.append(line)
                        elif line[0:1].isdigit() and line[1:2] == '.':
                            formatted.append(line)
                        else:
                            # Regular paragraph
                            formatted.append(f"{line}")
                    else:
                        formatted.append("")

                formatted.append("")  # Add spacing between sections

        formatted.append("---\n")  # Separator after thinking
        return '\n'.join(formatted)