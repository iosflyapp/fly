# API Reference Guide

## Overview

This document explains how the app fetches models from different AI providers.

## OpenAI API

### Endpoint
```
GET https://api.openai.com/v1/models
```

### Headers
```
Authorization: Bearer YOUR_API_KEY
Content-Type: application/json
```

### Response Format
```json
{
  "data": [
    {
      "id": "gpt-4o",
      "object": "model",
      "created": 1234567890,
      "owned_by": "system"
    }
  ]
}
```

### Implementation
- Fetches all available models
- Filters for chat models (contains "gpt", excludes "instruct")
- Sorts by priority: GPT-4o → GPT-4 Turbo → GPT-4 → GPT-3.5 Turbo

## Anthropic API

### Note
Anthropic doesn't provide a public models endpoint. The app validates the API key by making a test request.

### Validation Endpoint
```
POST https://api.anthropic.com/v1/messages
```

### Headers
```
x-api-key: YOUR_API_KEY
anthropic-version: 2023-06-01
Content-Type: application/json
```

### Test Request Body
```json
{
  "model": "claude-3-5-sonnet-20241022",
  "max_tokens": 1,
  "messages": [
    {
      "role": "user",
      "content": "test"
    }
  ]
}
```

### Implementation
- Sends minimal test request to validate API key
- Returns predefined list of Claude models
- Falls back gracefully if validation fails

## Google AI API

### Endpoint
```
GET https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_API_KEY
```

### Response Format
```json
{
  "models": [
    {
      "name": "models/gemini-2.0-flash-exp",
      "displayName": "Gemini 2.0 Flash",
      "supportedGenerationMethods": ["generateContent"]
    }
  ]
}
```

### Implementation
- Fetches all available models
- Strips "models/" prefix from names
- Filters for Gemini chat models
- Sorts by priority: Gemini 2.0 → Gemini 1.5 Pro → Gemini 1.5 Flash

## Custom API

### Requirements
Must be OpenAI-compatible API

### Endpoint Detection
```
If endpoint is: https://api.example.com/v1/chat/completions
Models endpoint: https://api.example.com/v1/models
```

### Headers
```
Authorization: Bearer YOUR_API_KEY
Content-Type: application/json
```

### Expected Response
Same format as OpenAI API (see above)

### Implementation
- Attempts to derive models endpoint from chat endpoint
- Falls back to empty list if fetch fails
- Works with: Ollama, LM Studio, LocalAI, etc.

## Error Handling

### Network Errors
- Connection timeout
- No internet connection
- DNS resolution failure

**Fallback**: Use default models list

### API Errors
- 401 Unauthorized (invalid API key)
- 403 Forbidden (insufficient permissions)
- 429 Too Many Requests (rate limited)
- 500 Server Error

**Fallback**: Use default models list + show error message

### Parsing Errors
- Invalid JSON response
- Unexpected response structure

**Fallback**: Use default models list

## Default Models

If API fetching fails, the app uses these default models:

### OpenAI
- gpt-4o
- gpt-4o-mini
- gpt-4-turbo
- gpt-3.5-turbo

### Anthropic
- claude-3-5-sonnet-20241022
- claude-3-5-haiku-20241022
- claude-3-opus-20240229

### Google AI
- gemini-2.0-flash-exp
- gemini-1.5-pro
- gemini-1.5-flash

### Custom
Empty list (must be configured manually)

## Rate Limiting

### Best Practices
- Cache fetched models locally
- Don't fetch on every app launch
- Manual "Fetch Models" button for refresh
- Auto-fetch only when API key changes

### Implementation
```swift
// Auto-fetch triggered when:
.onChange(of: apiKey) { _ in
    if !apiKey.isEmpty && apiKey.count > 20 {
        Task {
            await fetchModels()
        }
    }
}
```

## Security

### API Key Storage
- Stored in UserDefaults (local device only)
- Never transmitted except to respective API provider
- Can be hidden/shown with eye icon
- Cleared when configuration is deleted

### Best Practices
- Use environment-specific API keys
- Rotate keys regularly
- Set spending limits on provider dashboards
- Monitor API usage

## Testing API Keys

### Quick Test Commands

**OpenAI**
```bash
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

**Anthropic**
```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: YOUR_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":1,"messages":[{"role":"user","content":"test"}]}'
```

**Google AI**
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_API_KEY"
```

## Troubleshooting

### OpenAI: Empty Models List
- API key may not have models:read permission
- Check API key format (should start with sk-)
- Verify account is in good standing

### Anthropic: Validation Fails
- API key format incorrect (should start with sk-ant-)
- Check anthropic-version header matches
- Verify API access is enabled

### Google AI: No Models Returned
- API key may be restricted to specific APIs
- Enable "Generative Language API" in Google Cloud Console
- Check API key restrictions

### Custom: Connection Failed
- Verify endpoint URL is correct
- Check if server supports /models endpoint
- Ensure server is running and accessible
- Verify API key format matches server expectation
