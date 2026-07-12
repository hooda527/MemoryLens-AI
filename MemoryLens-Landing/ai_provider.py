import base64
import json
import re
import requests

class ExtractionProvider:
    def __init__(self, api_key: str, base_url: str = None):
        self.api_key = api_key
        self.base_url = base_url

    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        raise NotImplementedError()

    def chat(self, prompt: str) -> str:
        raise NotImplementedError()

    def test_connection(self) -> bool:
        raise NotImplementedError()

def strip_fences(text: str) -> str:
    text = text.strip()
    text = re.sub(r"^```[a-z]*\n?", "", text)
    text = re.sub(r"```$", "", text)
    return text.strip()

class GeminiProvider(ExtractionProvider):
    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={self.api_key}"
        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": mime_type, "data": b64}}
                ]
            }],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": 2048}
        }
        resp = requests.post(url, json=payload, timeout=45)
        resp.raise_for_status()
        data = resp.json()
        raw = data["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(strip_fences(raw))

    def chat(self, prompt: str) -> str:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={self.api_key}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.5, "maxOutputTokens": 2048}
        }
        resp = requests.post(url, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()["candidates"][0]["content"]["parts"][0]["text"]

    def test_connection(self) -> bool:
        url = f"https://generativelanguage.googleapis.com/v1beta/models?key={self.api_key}"
        resp = requests.get(url, timeout=10)
        resp.raise_for_status()
        return True

class OpenAIProvider(ExtractionProvider):
    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": "gpt-4o",
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}}
                    ]
                }
            ],
            "temperature": 0.1,
            "max_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=45)
        resp.raise_for_status()
        raw = resp.json()["choices"][0]["message"]["content"]
        return json.loads(strip_fences(raw))

    def chat(self, prompt: str) -> str:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": "gpt-4o-mini",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.5,
            "max_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]

    def test_connection(self) -> bool:
        url = "https://api.openai.com/v1/models"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
        return True

class ClaudeProvider(ExtractionProvider):
    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
        payload = {
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 2048,
            "temperature": 0.1,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": mime_type,
                                "data": b64
                            }
                        },
                        {"type": "text", "text": prompt}
                    ]
                }
            ]
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=45)
        resp.raise_for_status()
        raw = resp.json()["content"][0]["text"]
        return json.loads(strip_fences(raw))

    def chat(self, prompt: str) -> str:
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
        payload = {
            "model": "claude-3-haiku-20240307",
            "max_tokens": 2048,
            "temperature": 0.5,
            "messages": [{"role": "user", "content": prompt}]
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()["content"][0]["text"]

    def test_connection(self) -> bool:
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01"
        }
        payload = {
            "model": "claude-3-haiku-20240307",
            "max_tokens": 1,
            "messages": [{"role": "user", "content": "ping"}]
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=10)
        resp.raise_for_status()
        return True

class GroqProvider(ExtractionProvider):
    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": "llama-3.2-11b-vision-preview",
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}}
                    ]
                }
            ],
            "temperature": 0.1,
            "max_completion_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=45)
        resp.raise_for_status()
        raw = resp.json()["choices"][0]["message"]["content"]
        return json.loads(strip_fences(raw))

    def chat(self, prompt: str) -> str:
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": "llama3-8b-8192",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.5,
            "max_completion_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]

    def test_connection(self) -> bool:
        url = "https://api.groq.com/openai/v1/models"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
        return True

class CustomProvider(ExtractionProvider):
    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        if not self.base_url:
            raise ValueError("Base URL required for Custom provider")
        
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        url = f"{self.base_url.rstrip('/')}/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": "default", 
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}}
                    ]
                }
            ],
            "temperature": 0.1,
            "max_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=45)
        resp.raise_for_status()
        raw = resp.json()["choices"][0]["message"]["content"]
        return json.loads(strip_fences(raw))

    def chat(self, prompt: str) -> str:
        if not self.base_url:
            raise ValueError("Base URL required for Custom provider")
        
        url = f"{self.base_url.rstrip('/')}/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": "default",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.5,
            "max_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]

    def test_connection(self) -> bool:
        if not self.base_url:
            raise ValueError("Base URL required for Custom provider")
        
        url = f"{self.base_url.rstrip('/')}/models"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
        return True

def get_provider(provider_name: str, api_key: str, base_url: str = None) -> ExtractionProvider:
    if provider_name == "gemini":
        return GeminiProvider(api_key, base_url)
    elif provider_name == "openai":
        return OpenAIProvider(api_key, base_url)
    elif provider_name == "claude":
        return ClaudeProvider(api_key, base_url)
    elif provider_name == "groq":
        return GroqProvider(api_key, base_url)
    elif provider_name == "custom":
        return CustomProvider(api_key, base_url)
    else:
        raise ValueError(f"Unknown provider: {provider_name}")
