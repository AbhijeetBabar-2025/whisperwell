---
title: Local AI
description: Run Whisperwell with no cloud services, using a cleanup model on your own computer or network.
---

# Local AI

Everything can run without cloud services: WhisperKit for speech (the default) plus a local model for cleanup. Set the cleanup provider to **Local** in Settings, or `"cleanupProvider": "local"` in the config file, then start a model server.

## Pick a server

**LM Studio.** Load a model, open the Developer tab, and start the server. Use:

```json
{ "localLLMBaseURL": "http://127.0.0.1:1234/v1", "localLLMModel": "" }
```

An empty model name uses whichever model is loaded.

**Ollama.** Run `ollama pull llama3.2`, keep Ollama running, and keep the defaults.

**llama.cpp.** Start `llama-server -m model.gguf --port 8080`, then set `"localLLMBaseURL": "http://127.0.0.1:8080/v1"`.

Instruction-tuned models from 3B to 14B parameters, such as Qwen 2.5 Instruct or Llama 3.2, work well. Reasoning models work too: their `<think>` output is removed before inserting.

## A server on another machine

For example LM Studio at `http://10.0.0.82:1234/v1`:

- In LM Studio's server settings, turn on **Serve on Local Network**.
- Allow Whisperwell under System Settings › Privacy & Security › **Local Network**, then relaunch it. Until you do, macOS reports the connection as "offline" and the menu shows "⚠ not reachable". Hover over it for the reason.
- Reserve the server's IP address in your router so it doesn't change.

## Custom Whisper models

Fine-tune Whisper, convert it to Core ML with [whisperkittools](https://github.com/argmaxinc/whisperkittools), and either upload it to Hugging Face (`whisperModelRepo` + `whisperModel`) or point `whisperModelFolder` at it.
