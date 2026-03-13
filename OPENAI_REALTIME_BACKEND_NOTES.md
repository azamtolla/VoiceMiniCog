# OpenAI Realtime Backend Requirements

This document describes what your backend must implement to support OpenAI Realtime in the VoiceMiniCog iOS app.

## Required Endpoint

### GET /realtime-token

Returns an ephemeral OpenAI Realtime client secret for WebRTC connection.

**Request:**
```http
GET /realtime-token HTTP/1.1
Accept: application/json
```

**Response (200 OK):**
```json
{
  "client_secret": "ek_abc123...",
  "expires_at": "2024-12-17T12:00:00Z"
}
```

**Response Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `client_secret` | string | Yes | Ephemeral token from OpenAI (starts with `ek_`) |
| `expires_at` | string (ISO8601) | No | Token expiration time (typically 1 minute) |

## Backend Implementation

Your backend should call OpenAI's session creation endpoint:

```python
# Python/Flask example
import requests
from flask import Flask, jsonify
import os

app = Flask(__name__)
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")

@app.route("/realtime-token", methods=["GET"])
def get_realtime_token():
    response = requests.post(
        "https://api.openai.com/v1/realtime/sessions",
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json"
        },
        json={
            "model": "gpt-4o-realtime-preview-2024-12-17",
            "voice": "sage"
        }
    )

    if response.status_code != 200:
        return jsonify({"error": "Failed to create session"}), 500

    data = response.json()
    return jsonify({
        "client_secret": data["client_secret"]["value"],
        "expires_at": data["client_secret"]["expires_at"]
    })
```

## Security Notes

1. **Never store OpenAI API key in iOS app** - it must remain on your server
2. **Ephemeral tokens expire quickly** (~1 minute) - fetch fresh token for each session
3. **Rate limit the endpoint** - prevent abuse
4. **Consider authentication** - verify the iOS app/user before issuing tokens

## What Stays on Server vs iOS

| Component | Location | Notes |
|-----------|----------|-------|
| OpenAI API Key | Server only | Never exposed to client |
| Ephemeral token generation | Server | POST to OpenAI, return client_secret |
| WebRTC signaling | iOS app | Uses ephemeral token to authenticate |
| Audio streaming | iOS app (WebRTC) | Direct to OpenAI via WebRTC |
| CDT clock scoring | Server OR iOS | Existing endpoint still works, CoreML also available |

## WebRTC Connection Flow (iOS Side)

1. iOS calls `GET /realtime-token` to get ephemeral token
2. iOS creates WebRTC peer connection
3. iOS creates SDP offer
4. iOS sends offer to OpenAI with Authorization: `Bearer {client_secret}`
5. OpenAI returns SDP answer
6. WebRTC connection established
7. Audio flows bidirectionally via WebRTC media tracks
8. Control messages flow via WebRTC data channel

## Mini-Cog Session Instructions

When establishing the realtime session, send these system instructions via `session.update`:

```json
{
  "type": "session.update",
  "session": {
    "instructions": "You are conducting a Mini-Cog cognitive assessment. Guide the patient through: 1) Greeting and word registration (say 3 words, have them repeat), 2) Word recall after clock drawing. Speak slowly and clearly. Be patient and encouraging. Do not score the assessment yourself - just collect responses.",
    "voice": "sage",
    "input_audio_format": "pcm16",
    "output_audio_format": "pcm16",
    "turn_detection": {
      "type": "server_vad",
      "threshold": 0.5,
      "prefix_padding_ms": 300,
      "silence_duration_ms": 500
    }
  }
}
```

## Testing

1. Start your backend server
2. Test the endpoint:
   ```bash
   curl http://localhost:5001/realtime-token
   ```
3. Verify you get a `client_secret` starting with `ek_`
4. Token should be valid for ~1 minute

## Existing Backend Integration

Your current backend at `http://192.168.1.169:5001` already handles:
- `/predict-shulman-base64` - CDT scoring (keep this for fallback)
- `/voice-minicog/next-step` - Original flow (can be deprecated)

Add the `/realtime-token` endpoint alongside these.
