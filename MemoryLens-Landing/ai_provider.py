import base64
import json
import re
import requests

class ExtractionProvider:
    def __init__(self, api_key: str, base_url: str = None, model_name: str = None):
        self.api_key = api_key
        self.base_url = base_url
        self.model_name = model_name

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
    GEMINI_DEFAULT_MODEL = "gemini-1.5-flash"

    def _get_model(self):
        return self.model_name or self.GEMINI_DEFAULT_MODEL

    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self._get_model()}:generateContent?key={self.api_key}"
        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": mime_type, "data": b64}}
                ]
            }],
            "safetySettings": [
                {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
                {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
                {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
                {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"}
            ],
            "generationConfig": {
                "temperature": 0.1, 
                "maxOutputTokens": 2048,
                "responseMimeType": "application/json"
            }
        }
        resp = requests.post(url, json=payload, timeout=45)
        self._check_response(resp)
        data = resp.json()
        
        # Check if content was blocked
        candidate = data.get("candidates", [{}])[0]
        if "content" not in candidate:
            finish_reason = candidate.get("finishReason", "UNKNOWN")
            raise ValueError(f"Provider blocked the response (Reason: {finish_reason}). Try a different image.")
            
        raw = candidate["content"]["parts"][0]["text"]
        return json.loads(strip_fences(raw))

    def chat(self, prompt: str) -> str:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self._get_model()}:generateContent?key={self.api_key}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.5, "maxOutputTokens": 2048}
        }
        resp = requests.post(url, json=payload, timeout=30)
        self._check_response(resp)
        return resp.json()["candidates"][0]["content"]["parts"][0]["text"]

    def _check_response(self, resp):
        """Raise HTTPError with the real Google error message."""
        if not resp.ok:
            try:
                msg = resp.json()["error"]["message"]
            except Exception:
                msg = f"HTTP {resp.status_code}"
            raise requests.exceptions.HTTPError(msg, response=resp)

    def test_connection(self) -> bool:
        """Test connection by sending a minimal content generation request."""
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self._get_model()}:generateContent?key={self.api_key}"
        payload = {
            "contents": [{"parts": [{"text": "ping"}]}],
            "generationConfig": {"maxOutputTokens": 1}
        }
        resp = requests.post(url, json=payload, timeout=10)
        self._check_response(resp)
        return True

class OpenAIProvider(ExtractionProvider):
    def analyze(self, image_bytes: bytes, mime_type: str, prompt: str) -> dict:
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": self.model_name or "gpt-4o",
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
            "model": self.model_name or "gpt-4o-mini",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.5,
            "max_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]

    def test_connection(self) -> bool:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": self.model_name or "gpt-4o-mini",
            "messages": [{"role": "user", "content": "ping"}],
            "max_tokens": 1
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=10)
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
            "model": self.model_name or "claude-3-5-sonnet-20241022",
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
            "model": self.model_name or "claude-3-haiku-20240307",
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
            "model": self.model_name or "llama-3.2-11b-vision-preview",
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
            "model": self.model_name or "llama3-8b-8192",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.5,
            "max_completion_tokens": 2048
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]

    def test_connection(self) -> bool:
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": self.model_name or "llama3-8b-8192",
            "messages": [{"role": "user", "content": "ping"}],
            "max_tokens": 1
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=10)
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
            "model": self.model_name or "default", 
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
            "model": self.model_name or "default",
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
        
        url = f"{self.base_url.rstrip('/')}/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}"}
        payload = {
            "model": self.model_name or "default",
            "messages": [{"role": "user", "content": "ping"}],
            "max_tokens": 1
        }
        resp = requests.post(url, headers=headers, json=payload, timeout=10)
        resp.raise_for_status()
        return True

def get_provider(provider_name: str, api_key: str, base_url: str = None, model_name: str = None) -> ExtractionProvider:
    if provider_name == "gemini":
        return GeminiProvider(api_key, base_url, model_name)
    elif provider_name == "openai":
        return OpenAIProvider(api_key, base_url, model_name)
    elif provider_name == "claude":
        return ClaudeProvider(api_key, base_url, model_name)
    elif provider_name == "groq":
        return GroqProvider(api_key, base_url, model_name)
    elif provider_name == "custom":
        return CustomProvider(api_key, base_url, model_name)
    else:
        raise ValueError(f"Unknown provider: {provider_name}")
