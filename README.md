# PicoAgent

A self-contained local AI coding agent: **Qwythos 9B** reasoning model running on
your Mac via `llama.cpp`, driven by the **[pi](https://pi.dev)** coding agent.

One script downloads the model, builds `llama.cpp`, installs `pi`, registers
Qwythos as a custom provider, and starts the OpenAI-compatible server.

## Requirements

- macOS Apple Silicon (M-series), 16 GB RAM minimum
- Xcode command-line tools (`xcode-select --install`)
- Node.js 20+ (`node --version`)
- ~6 GB free disk for the model + ~1 GB for `llama.cpp` build

## Quick start

```bash
git clone git@github.com:0xK8oX/pico-agent.git
cd pico-agent
chmod +x setup.sh
./setup.sh
```

The first run takes 10–30 minutes (model download + llama.cpp build). When it
finishes you'll see a health check and a quick generation test.

Then in any project:

```bash
cd /your/project
pi
```

Qwythos is set as the default model — no `--model` flag needed. To override
per-run:

```bash
pi --model Qwythos           # explicit
pi --model <other-provider>:<model>
```

Or non-interactive:

```bash
pi --print "Summarize this repository"
```

## What the setup script does

| Step | Action |
|------|--------|
| 1 | Downloads `Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf` (5.2 GB, v2) via `aria2c` or `curl` |
| 2 | Clones and builds `llama.cpp` with Metal GPU support |
| 3 | Installs the `pi` coding agent globally via npm |
| 4 | Writes a pi extension that registers Qwythos as a custom OpenAI-compatible provider |
| 4b | Sets Qwythos as pi's default model (`defaultProvider` + `defaultModel` in `~/.pi/agent/settings.json`) |
| 5 | Starts `llama-server` with M4-optimized flags |
| 6 | Verifies server health + pi can see the model |

## Server configuration (M4 16GB optimized)

```
--model              Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf
--ctx-size           16384
--n-gpu-layers       999      (all layers on Metal)
--flash-attn         on
--cache-type-k       q8_0     (8-bit KV cache, saves memory)
--cache-type-v       q8_0
--threads            8
--temp               0.6      (per model card)
--top-p              0.95
--top-k              20
--repeat-penalty     1.05
```

Expected on Apple M4 16GB: **~16 tokens/sec** generation, **~5.7 GB RSS**.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PICOAGENT_PORT` | `23456` | llama-server port |
| `PICOAGENT_BASE_URL` | `http://127.0.0.1:23456/v1` | Override in pi extension |
| `HF_TOKEN` | (empty) | Optional HuggingFace token for higher rate limits |

## Files

```
pico-agent/
├── setup.sh           # one-shot setup script
├── stop.sh            # stop the running server
└── README.md
```

The script also writes:
- `~/.pi/agent/extensions/qwythos-local.ts` — pi provider extension
- `~/.pi/agent/extensions/package.json` — extension package
- `/tmp/picoagent-server.log` — server log
- `/tmp/picoagent-server.pid` — server PID

## Stop the server

```bash
./stop.sh
```

## Why Q4_K_M?

Tested all four quants on this hardware. Q4_K_M is the sweet spot:

| Quant | Gen t/s | RSS | GSM8K | Agentic |
|-------|---------|-----|-------|---------|
| **Q4_K_M** | **15.8** | **5.4 GB** | **100%** | **100%** |
| Q6_K | 12.6 | 7.7 GB | 100% | 100% |

Q6_K gives zero quality gain but 40% more memory and 20% slower. MTP
speculative decoding actually slows down on 16 GB Mac due to memory pressure.

## Troubleshooting

**`pi --list-models` shows no Qwythos** — make sure `~/.pi/agent/extensions/package.json` has `"type": "module"`, then run `pi --list-models` again.

**Server fails to start** — check `/tmp/picoagent-server.log`. Common cause: another process on port 23456. Change with `PICOAGENT_PORT=23457 ./setup.sh`.

**Slow download** — install aria2 (`brew install aria2`) for multi-stream download. Optionally set `HF_TOKEN` for higher HuggingFace rate limits.

**`--chat-template auto` warning** — do NOT add this flag to `llama-server`. It breaks Qwythos v2's embedded thinking template.

## License

The setup script is MIT. The model weights follow
[empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF](https://huggingface.co/empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF)
(Apache 2.0). `llama.cpp` is MIT. `pi` is MIT.
