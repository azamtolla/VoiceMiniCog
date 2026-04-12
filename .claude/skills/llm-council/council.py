#!/usr/bin/env python3
"""LLM Council — polls multiple models, collects peer reviews, synthesizes."""

import os
import json
import argparse
import urllib.request

# --- Config ---
ADVISORS = [
    {
        "name": "Pragmatist",
        "system": "You are a pragmatic senior engineer. Focus on what works NOW. "
                  "Shortest path to a working solution. Flag over-engineering.",
        "provider": "openai",
        "model": "gpt-4o"
    },
    {
        "name": "Skeptic",
        "system": "You are a skeptical code reviewer. Find holes, edge cases, and "
                  "failure modes. Assume things WILL break. Challenge assumptions.",
        "provider": "openai",
        "model": "gpt-4o"
    },
    {
        "name": "Researcher",
        "system": "You are a research-oriented advisor. Cite best practices, Apple "
                  "HIG guidelines, HIPAA requirements, and clinical validation standards. "
                  "Ground advice in evidence.",
        "provider": "gemini",
        "model": "gemini-2.5-flash"
    },
    {
        "name": "UserAdvocate",
        "system": "You are a clinician UX advocate. Every answer must center the "
                  "primary care physician and the patient. How does this feel in a "
                  "busy clinic? Is it fast enough? Clear enough?",
        "provider": "gemini",
        "model": "gemini-2.5-flash"
    },
    {
        "name": "Architect",
        "system": "You are a systems architect. Think about maintainability, scale, "
                  "HIPAA compliance architecture, data flow, and technical debt. "
                  "Consider how this decision affects the app in 2 years.",
        "provider": "openrouter",
        "model": "deepseek/deepseek-chat-v3-0324"
    }
]


def call_openai(model, system, prompt):
    key = os.environ.get("OPENAI_API_KEY", "")
    data = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 1500
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=data,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    )
    resp = json.loads(urllib.request.urlopen(req).read())
    return resp["choices"][0]["message"]["content"]


def call_gemini(model, system, prompt):
    key = os.environ.get("GEMINI_API_KEY", "")
    data = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "systemInstruction": {"parts": [{"text": system}]},
        "generationConfig": {"maxOutputTokens": 1500}
    }).encode()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req).read())
    return resp["candidates"][0]["content"]["parts"][0]["text"]


def call_openrouter(model, system, prompt):
    key = os.environ.get("OPENROUTER_API_KEY", "")
    data = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 1500
    }).encode()
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=data,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    )
    resp = json.loads(urllib.request.urlopen(req).read())
    return resp["choices"][0]["message"]["content"]


PROVIDERS = {
    "openai": call_openai,
    "gemini": call_gemini,
    "openrouter": call_openrouter
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--question", required=True)
    args = parser.parse_args()

    question = args.question
    print(f"\n{'='*60}")
    print("LLM COUNCIL — PHASE 1: INDEPENDENT RESPONSES")
    print(f"{'='*60}\n")

    # Phase 1: Collect independent responses
    responses = {}
    for advisor in ADVISORS:
        print(f"  Polling {advisor['name']} ({advisor['provider']}/{advisor['model']})...")
        try:
            fn = PROVIDERS[advisor["provider"]]
            resp = fn(advisor["model"], advisor["system"], question)
            responses[advisor["name"]] = resp
            print(f"  ✓ {advisor['name']} responded ({len(resp)} chars)")
        except Exception as e:
            responses[advisor["name"]] = f"[ERROR: {e}]"
            print(f"  ✗ {advisor['name']} failed: {e}")

    # Phase 2: Anonymous peer review
    print(f"\n{'='*60}")
    print("LLM COUNCIL — PHASE 2: ANONYMOUS PEER REVIEW")
    print(f"{'='*60}\n")

    anonymized = "\n\n".join(
        f"--- Response {chr(65+i)} ---\n{resp}"
        for i, (name, resp) in enumerate(responses.items())
    )

    review_prompt = (
        f"Original question: {question}\n\n"
        f"Below are 5 anonymous responses. Rank them 1-5 (best to worst). "
        f"For each, give a 1-sentence strength and 1-sentence weakness.\n\n"
        f"{anonymized}"
    )

    reviews = {}
    for advisor in ADVISORS[:3]:  # Use 3 reviewers to save cost
        print(f"  Review by {advisor['name']}...")
        try:
            fn = PROVIDERS[advisor["provider"]]
            rev = fn(advisor["model"], "You are a fair, critical peer reviewer.", review_prompt)
            reviews[advisor["name"]] = rev
            print(f"  ✓ Review complete")
        except Exception as e:
            reviews[advisor["name"]] = f"[ERROR: {e}]"
            print(f"  ✗ Review failed: {e}")

    # Phase 3: Chairman synthesis
    print(f"\n{'='*60}")
    print("LLM COUNCIL — PHASE 3: CHAIRMAN SYNTHESIS")
    print(f"{'='*60}\n")

    synthesis_prompt = (
        f"You are the chairman of an AI advisory council for a clinical iOS app "
        f"(Voice MiniCog — cognitive screening for Alzheimer's/MCI detection).\n\n"
        f"Original question: {question}\n\n"
        f"RESPONSES:\n{anonymized}\n\n"
        f"PEER REVIEWS:\n" +
        "\n\n".join(f"--- Reviewer {i+1} ---\n{r}" for i, r in enumerate(reviews.values())) +
        f"\n\nSynthesize a final verdict with:\n"
        f"1. VERDICT — the best answer\n"
        f"2. CONSENSUS — where all advisors agreed\n"
        f"3. DISSENT — where they disagreed\n"
        f"4. RISK FLAGS — anything flagged by 2+ advisors\n"
        f"5. RECOMMENDATION — final actionable advice for the developer"
    )

    try:
        verdict = call_openai("gpt-4o", "You are a fair chairman synthesizing expert opinions.", synthesis_prompt)
    except Exception as e:
        verdict = f"Chairman synthesis failed: {e}"

    # Output everything
    print(f"\n{'='*60}")
    print("INDIVIDUAL RESPONSES")
    print(f"{'='*60}")
    for name, resp in responses.items():
        print(f"\n### {name}\n{resp}")

    print(f"\n{'='*60}")
    print("PEER REVIEWS")
    print(f"{'='*60}")
    for name, rev in reviews.items():
        print(f"\n### Review by {name}\n{rev}")

    print(f"\n{'='*60}")
    print("FINAL VERDICT")
    print(f"{'='*60}")
    print(verdict)


if __name__ == "__main__":
    main()
