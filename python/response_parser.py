"""
Enhanced response parser for various LLM output formats
"""
import re
import json
from typing import Dict, Any, Optional, List
import xml.etree.ElementTree as ET


class ResponseParser:
    """Parse various LLM response formats intelligently"""

    def __init__(self):
        # Common patterns for different LLM response formats
        self.patterns = {
            'xml_tags': re.compile(r'<(\w+)>(.*?)</\1>', re.DOTALL),
            'markdown_code': re.compile(r'```(?:(\w+))?\n(.*?)\n```', re.DOTALL),
            'inline_code': re.compile(r'`([^`]+)`'),
            'json_block': re.compile(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', re.DOTALL),
            'numbered_list': re.compile(r'^\d+\.\s+(.+)$', re.MULTILINE),
            'bullet_list': re.compile(r'^[-*]\s+(.+)$', re.MULTILINE),
            'header': re.compile(r'^#+\s+(.+)$', re.MULTILINE),
            'key_value': re.compile(r'^(\w+):\s*(.+)$', re.MULTILINE),
            'thinking_tags': re.compile(r'<(?:think|thinking|thought|reasoning)>.*?</(?:think|thinking|thought|reasoning)>', re.DOTALL),
            'assistant_tags': re.compile(r'<(?:assistant|response|answer)>(.*?)</(?:assistant|response|answer)>', re.DOTALL),
            'system_tags': re.compile(r'<(?:system|context|background)>.*?</(?:system|context|background)>', re.DOTALL),
        }

        # Common LLM output structures
        self.llm_formats = {
            'openai': self._parse_openai_format,
            'anthropic': self._parse_anthropic_format,
            'llama': self._parse_llama_format,
            'gemini': self._parse_gemini_format,
            'mistral': self._parse_mistral_format,
            'deepseek': self._parse_deepseek_format,
        }

    def parse(self, response: str, hint: Optional[str] = None) -> Dict[str, Any]:
        """
        Parse response with optional hint about the LLM type

        Args:
            response: Raw response from LLM
            hint: Optional hint about which LLM generated this (e.g., 'openai', 'anthropic')

        Returns:
            Parsed response with code, explanation, format info, and raw response
        """
        # Store original
        original = response
        result = {
            'raw_response': original,
            'format_detected': 'unknown',
            'parsed_sections': {},
            'thinking': None  # Store thinking content separately
        }

        # Try specific LLM format if hint provided
        if hint and hint.lower() in self.llm_formats:
            specific_result = self.llm_formats[hint.lower()](response)
            if specific_result.get('code'):
                result.update(specific_result)
                result['format_detected'] = hint.lower()
                return result

        # Auto-detect format
        detected_format = self._detect_format(response)
        result['format_detected'] = detected_format

        # Extract thinking/reasoning tags but keep them
        thinking_content = self._extract_thinking_tags(response)
        if thinking_content:
            result['thinking'] = thinking_content
            # Remove thinking tags from main response for parsing
            response = self._remove_thinking_tags(response)

        # Extract main content from assistant tags if present
        assistant_content = self._extract_assistant_content(response)
        if assistant_content:
            response = assistant_content

        # Parse based on detected format
        if detected_format == 'xml_structured':
            result.update(self._parse_xml_structured(response))
        elif detected_format == 'json_response':
            result.update(self._parse_json_response(response))
        elif detected_format == 'markdown_formatted':
            result.update(self._parse_markdown_formatted(response))
        elif detected_format == 'key_value_pairs':
            result.update(self._parse_key_value_format(response))
        elif detected_format == 'plain_code':
            result.update(self._parse_plain_code(response))
        else:
            # Try generic parsing
            result.update(self._parse_generic(response))

        return result

    def _detect_format(self, response: str) -> str:
        """Detect the response format"""
        response = response.strip()

        # Check for XML-like structure
        if re.search(r'<\w+>.*</\w+>', response, re.DOTALL):
            return 'xml_structured'

        # Check for JSON
        if response.startswith('{') and response.endswith('}'):
            try:
                json.loads(response)
                return 'json_response'
            except:
                pass

        # Check for markdown with code blocks
        if '```' in response:
            return 'markdown_formatted'

        # Check for key-value pairs
        if re.search(r'^\w+:\s*.+$', response, re.MULTILINE):
            return 'key_value_pairs'

        # Check if it's just code
        if self._looks_like_code(response):
            return 'plain_code'

        return 'mixed_format'

    def _looks_like_code(self, text: str) -> bool:
        """Check if text looks like code"""
        code_indicators = [
            r'^\s*(def|class|function|const|let|var|import|from|export)\s+',
            r'^\s*(if|for|while|switch|case|return)\s*[\(\{]',
            r'[\{\}\[\]\(\);]',
            r'=>|->|::|<<|>>',
            r'^\s*[#/]{1,2}\s*\w+',  # Comments
        ]

        lines = text.split('\n')
        code_line_count = 0

        for line in lines:
            for pattern in code_indicators:
                if re.search(pattern, line):
                    code_line_count += 1
                    break

        # If more than 50% of non-empty lines look like code
        non_empty_lines = [l for l in lines if l.strip()]
        if non_empty_lines:
            return code_line_count / len(non_empty_lines) > 0.5
        return False

    def _extract_thinking_tags(self, response: str) -> Optional[Dict[str, str]]:
        """Extract thinking/reasoning tag contents"""
        thinking_sections = {}

        # Find all thinking-like tags
        thinking_patterns = [
            (r'<think>(.*?)</think>', 'thinking'),
            (r'<thinking>(.*?)</thinking>', 'thinking'),
            (r'<thought>(.*?)</thought>', 'thought'),
            (r'<reasoning>(.*?)</reasoning>', 'reasoning'),
            (r'<analysis>(.*?)</analysis>', 'analysis'),
            (r'<planning>(.*?)</planning>', 'planning'),
            (r'<approach>(.*?)</approach>', 'approach'),
            (r'<strategy>(.*?)</strategy>', 'strategy'),
            (r'<scratch>(.*?)</scratch>', 'scratch'),
            (r'<work>(.*?)</work>', 'work'),
            (r'<internal>(.*?)</internal>', 'internal'),
        ]

        for pattern, tag_name in thinking_patterns:
            matches = re.findall(pattern, response, re.DOTALL)
            if matches:
                # Combine multiple matches of the same tag type
                thinking_sections[tag_name] = '\n\n'.join(match.strip() for match in matches)

        return thinking_sections if thinking_sections else None

    def _remove_thinking_tags(self, response: str) -> str:
        """Remove thinking/reasoning tags"""
        return self.patterns['thinking_tags'].sub('', response).strip()

    def _extract_assistant_content(self, response: str) -> Optional[str]:
        """Extract content from assistant tags"""
        match = self.patterns['assistant_tags'].search(response)
        if match:
            return match.group(1).strip()
        return None

    def _parse_xml_structured(self, response: str) -> Dict[str, Any]:
        """Parse XML-structured response"""
        result = {}

        # Extract code from XML tags
        code_patterns = [
            r'<code>(.*?)</code>',
            r'<implementation>(.*?)</implementation>',
            r'<solution>(.*?)</solution>',
            r'<answer>(.*?)</answer>',
        ]

        for pattern in code_patterns:
            match = re.search(pattern, response, re.DOTALL)
            if match:
                result['code'] = match.group(1).strip()
                break

        # Extract explanation
        explanation_patterns = [
            r'<explanation>(.*?)</explanation>',
            r'<description>(.*?)</description>',
            r'<reasoning>(.*?)</reasoning>',
            r'<context>(.*?)</context>',
        ]

        for pattern in explanation_patterns:
            match = re.search(pattern, response, re.DOTALL)
            if match:
                result['explanation'] = match.group(1).strip()
                break

        # Parse all XML tags into sections
        all_tags = self.patterns['xml_tags'].findall(response)
        result['parsed_sections'] = {tag: content.strip() for tag, content in all_tags}

        return result

    def _parse_json_response(self, response: str) -> Dict[str, Any]:
        """Parse JSON response"""
        try:
            data = json.loads(response)
            result = {}

            # Common JSON keys for code
            code_keys = ['code', 'implementation', 'solution', 'answer', 'result']
            for key in code_keys:
                if key in data:
                    result['code'] = data[key]
                    break

            # Common JSON keys for explanation
            explanation_keys = ['explanation', 'description', 'reasoning', 'context', 'notes']
            for key in explanation_keys:
                if key in data:
                    result['explanation'] = data[key]
                    break

            result['parsed_sections'] = data
            return result
        except:
            return {}

    def _parse_markdown_formatted(self, response: str) -> Dict[str, Any]:
        """Parse markdown-formatted response"""
        result = {}

        # Extract code blocks
        code_blocks = self.patterns['markdown_code'].findall(response)
        if code_blocks:
            # Take the first substantial code block
            for lang, code in code_blocks:
                if len(code.strip()) > 10:  # Ignore tiny snippets
                    result['code'] = code.strip()
                    result['code_language'] = lang or 'unknown'
                    break

        # Extract explanation (text outside code blocks)
        explanation_text = response
        for match in self.patterns['markdown_code'].finditer(response):
            explanation_text = explanation_text.replace(match.group(0), '')

        explanation_text = explanation_text.strip()
        if explanation_text:
            result['explanation'] = explanation_text

        # Parse sections by headers
        sections = {}
        current_section = 'intro'
        lines = response.split('\n')
        section_content = []

        for line in lines:
            header_match = self.patterns['header'].match(line)
            if header_match:
                if section_content:
                    sections[current_section] = '\n'.join(section_content).strip()
                current_section = header_match.group(1).lower().replace(' ', '_')
                section_content = []
            else:
                section_content.append(line)

        if section_content:
            sections[current_section] = '\n'.join(section_content).strip()

        if sections:
            result['parsed_sections'] = sections

        return result

    def _parse_key_value_format(self, response: str) -> Dict[str, Any]:
        """Parse key-value format response"""
        result = {}
        kv_pairs = {}

        for match in self.patterns['key_value'].finditer(response):
            key = match.group(1).lower().replace(' ', '_')
            value = match.group(2).strip()
            kv_pairs[key] = value

        # Map common keys to standard fields
        code_keys = ['code', 'implementation', 'solution', 'answer', 'result']
        for key in code_keys:
            if key in kv_pairs:
                result['code'] = kv_pairs[key]
                break

        explanation_keys = ['explanation', 'description', 'reasoning', 'notes']
        for key in explanation_keys:
            if key in kv_pairs:
                result['explanation'] = kv_pairs[key]
                break

        result['parsed_sections'] = kv_pairs
        return result

    def _parse_plain_code(self, response: str) -> Dict[str, Any]:
        """Parse plain code response"""
        return {
            'code': response.strip(),
            'explanation': 'Direct code implementation',
            'format_detected': 'plain_code'
        }

    def _parse_generic(self, response: str) -> Dict[str, Any]:
        """Generic parsing fallback"""
        result = {}

        # Try to extract any code blocks
        code_blocks = self.patterns['markdown_code'].findall(response)
        if code_blocks:
            result['code'] = code_blocks[0][1] if isinstance(code_blocks[0], tuple) else code_blocks[0]
        elif self._looks_like_code(response):
            result['code'] = response.strip()

        # Try to separate code from explanation
        if not result.get('code'):
            lines = response.split('\n')
            code_lines = []
            explanation_lines = []

            in_code = False
            for line in lines:
                if self._looks_like_code(line):
                    in_code = True
                    code_lines.append(line)
                elif in_code and line.strip() == '':
                    code_lines.append(line)
                else:
                    in_code = False
                    explanation_lines.append(line)

            if code_lines:
                result['code'] = '\n'.join(code_lines).strip()
            if explanation_lines:
                result['explanation'] = '\n'.join(explanation_lines).strip()

        return result

    # Specific LLM format parsers
    def _parse_openai_format(self, response: str) -> Dict[str, Any]:
        """Parse OpenAI-style responses"""
        # OpenAI often returns clean code or uses markdown
        return self._parse_markdown_formatted(response)

    def _parse_anthropic_format(self, response: str) -> Dict[str, Any]:
        """Parse Anthropic Claude-style responses"""
        # Claude often uses thinking tags and structured output
        response = self._remove_thinking_tags(response)

        # Check for XML-like structure that Claude sometimes uses
        if '<code>' in response or '<implementation>' in response:
            return self._parse_xml_structured(response)

        return self._parse_markdown_formatted(response)

    def _parse_llama_format(self, response: str) -> Dict[str, Any]:
        """Parse Llama-style responses"""
        # Llama models often use markdown or plain text
        if '```' in response:
            return self._parse_markdown_formatted(response)
        return self._parse_generic(response)

    def _parse_gemini_format(self, response: str) -> Dict[str, Any]:
        """Parse Google Gemini-style responses"""
        # Gemini often uses markdown with clear sections
        return self._parse_markdown_formatted(response)

    def _parse_mistral_format(self, response: str) -> Dict[str, Any]:
        """Parse Mistral-style responses"""
        # Mistral tends to use clean markdown
        return self._parse_markdown_formatted(response)

    def _parse_deepseek_format(self, response: str) -> Dict[str, Any]:
        """Parse DeepSeek-style responses"""
        # DeepSeek often includes reasoning steps
        response = self._remove_thinking_tags(response)

        if '```' in response:
            return self._parse_markdown_formatted(response)
        return self._parse_generic(response)