#!/usr/bin/env bash
# PicoAgent — one-shot setup script
#
# Downloads the Qwythos 9B Q4_K_M v2 GGUF, builds llama.cpp with Metal,
# installs the pi coding agent, registers Qwythos as a custom provider,
# starts the OpenAI-compatible server, and verifies everything works.
#
# Tested on macOS Apple Silicon (M-series). 16 GB RAM minimum.

set -euo pipefail

# ============================================================================
# Config
# ============================================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="$PROJECT_DIR/llama.cpp"
MODELS_DIR="$LLAMA_DIR/models"
MODEL_FILE="$MODELS_DIR/Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF/resolve/main/Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf"
LLAMA_REPO="https://github.com/ggml-org/llama.cpp.git"
PI_PKG="@earendil-works/pi-coding-agent"
PORT="${PICOAGENT_PORT:-23456}"
HF_TOKEN="${HF_TOKEN:-}"  # optional, for higher rate limits

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $*"; }
info() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*" >&2; }

# ============================================================================
# Preflight checks
# ============================================================================
preflight() {
  log "Preflight checks"

  if [[ "$(uname)" != "Darwin" ]]; then
    warn "This script is tested on macOS Apple Silicon. Proceeding on $(uname)..."
  fi
  if [[ "$(uname -m)" != "arm64" ]]; then
    warn "Not arm64 ($(uname -m)). Metal GPU offload may not work."
  fi

  for cmd in git cmake curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "Missing required command: $cmd"
      exit 1
    fi
  done

  if ! command -v node >/dev/null 2>&1; then
    err "Node.js not found. Install from https://nodejs.org/ (v20+ recommended)."
    exit 1
  fi
  if ! command -v npm >/dev/null 2>&1; then
    err "npm not found."
    exit 1
  fi

  info "node $(node --version)  npm $(npm --version)  OK"
}

# ============================================================================
# 1. Download model
# ============================================================================
download_model() {
  log "Step 1: Download Qwythos 9B Q4_K_M v2 GGUF"

  mkdir -p "$MODELS_DIR"

  if [[ -f "$MODEL_FILE" ]]; then
    local size
    size=$(stat -f%z "$MODEL_FILE" 2>/dev/null || stat -c%s "$MODEL_FILE" 2>/dev/null || echo 0)
    if (( size > 5000000000 )); then
      info "Model already exists ($(du -h "$MODEL_FILE" | cut -f1)), skipping."
      return
    fi
  fi

  # Try aria2c first (faster, multi-stream), fall back to curl
  if command -v aria2c >/dev/null 2>&1; then
    info "Using aria2c (8 streams)..."
    local -a hdrs=()
    [[ -n "$HF_TOKEN" ]] && hdrs+=(--header="Authorization: Bearer $HF_TOKEN")
    aria2c -s 8 -x 8 -k 5M -c \
      "${hdrs[@]}" \
      -d "$MODELS_DIR" \
      -o "$(basename "$MODEL_FILE")" \
      "$MODEL_URL"
  else
    warn "aria2c not found, using curl (slower). Install with: brew install aria2"
    local -a hdrs=()
    [[ -n "$HF_TOKEN" ]] && hdrs+=(-H "Authorization: Bearer $HF_TOKEN")
    curl -L -C - "${hdrs[@]}" -o "$MODEL_FILE" "$MODEL_URL"
  fi

  log "Model downloaded: $(du -h "$MODEL_FILE" | cut -f1)"
}

# ============================================================================
# 2. Build llama.cpp
# ============================================================================
build_llama() {
  log "Step 2: Build llama.cpp with Metal"

  if [[ ! -d "$LLAMA_DIR/.git" ]]; then
    git clone --depth 1 "$LLAMA_REPO" "$LLAMA_DIR"
  else
    info "llama.cpp already cloned."
  fi

  if [[ -x "$LLAMA_DIR/build/bin/llama-server" ]]; then
    info "llama-server already built."
    return
  fi

  cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" \
    -DGGML_METAL=ON \
    -DLLAMA_BUILD_SERVER=ON
  cmake --build "$LLAMA_DIR/build" \
    --target llama-server llama-cli \
    -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

  if [[ ! -x "$LLAMA_DIR/build/bin/llama-server" ]]; then
    err "Build failed: llama-server not found at $LLAMA_DIR/build/bin/"
    exit 1
  fi
  log "llama.cpp built."
}

# ============================================================================
# 3. Install pi
# ============================================================================
install_pi() {
  log "Step 3: Install pi coding agent"

  if command -v pi >/dev/null 2>&1; then
    info "pi already installed: $(pi --version 2>&1 | head -1)"
  else
    npm install -g --ignore-scripts "$PI_PKG"
  fi
}

# ============================================================================
# 4. Register Qwythos provider extension
# ============================================================================
register_extension() {
  log "Step 4: Register Qwythos provider with pi"

  local ext_dir="$HOME/.pi/agent/extensions"
  mkdir -p "$ext_dir"

  if [[ ! -f "$ext_dir/package.json" ]]; then
    cat > "$ext_dir/package.json" <<'PKG'
{
  "name": "picoagent-extensions",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "dependencies": {
    "@earendil-works/pi-coding-agent": "*"
  }
}
PKG
    (cd "$ext_dir" && npm install --no-audit --no-fund --ignore-scripts) >/dev/null 2>&1 || true
  fi

  # Always overwrite to keep config in sync with PicoAgent
  cat > "$ext_dir/qwythos-local.ts" <<'TS'
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerProvider("qwythos-local", {
    name: "Qwythos 9B (local llama-server)",
    baseUrl: process.env.PICOAGENT_BASE_URL || "http://127.0.0.1:23456/v1",
    apiKey: "no-key-required",
    api: "openai-completions",
    models: [
      {
        id: "Qwythos",
        name: "Qwythos 9B Claude Mythos 5 1M (Q4_K_M v2)",
        reasoning: true,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 16384,
        maxTokens: 8192,
      },
    ],
  });
}
TS

  info "Extension written: $ext_dir/qwythos-local.ts"
}

# ============================================================================
# 4b. Set Qwythos as pi's default model
# ============================================================================
set_default_model() {
  log "Step 4b: Set Qwythos as pi's default model"

  local settings_file="$HOME/.pi/agent/settings.json"
  mkdir -p "$(dirname "$settings_file")"

  if [[ -f "$settings_file" ]]; then
    # Merge in defaultProvider/defaultModel if missing
    python3 - "$settings_file" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
s.setdefault("defaultProvider", "qwythos-local")
s.setdefault("defaultModel", "Qwythos")
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
PY
  else
    cat > "$settings_file" <<'JSON'
{
  "theme": "dark",
  "defaultProvider": "qwythos-local",
  "defaultModel": "Qwythos"
}
JSON
  fi
  info "Settings updated: $settings_file (defaultProvider=qwythos-local, defaultModel=Qwythos)"
}

# ============================================================================
# 5. Start llama-server
# ============================================================================
start_server() {
  log "Step 5: Start llama-server (M4 16GB optimized config)"

  # Stop any existing instance
  pkill -f "llama-server.*Qwythos" 2>/dev/null || true
  sleep 2

  # M4-optimized flags:
  #   --n-gpu-layers 999    : offload all layers to Metal GPU
  #   --flash-attn on        : flash attention
  #   --cache-type-k/v q8_0  : 8-bit KV cache (saves memory)
  #   --threads 8            : prompt processing threads
  #   --ctx-size 16384       : 16K context (Agent golden setting)
  #   Sampling per model card: temp=0.6, top_p=0.95, top_k=20, repeat_penalty=1.05
  #   NO --chat-template auto (breaks Qwythos v2 thinking mode)
  #   NO --mmap, NO MTP draft (slower on 16GB Mac due to memory pressure)
  nohup "$LLAMA_DIR/build/bin/llama-server" \
    --model "$MODEL_FILE" \
    --port "$PORT" \
    --host 0.0.0.0 \
    --ctx-size 16384 \
    --n-gpu-layers 999 \
    --flash-attn on \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --threads 8 \
    --temp 0.6 \
    --top-p 0.95 \
    --top-k 20 \
    --repeat-penalty 1.05 \
    > /tmp/picoagent-server.log 2>&1 &

  local pid=$!
  echo "$pid" > /tmp/picoagent-server.pid
  disown
  info "llama-server PID $pid, waiting for health..."

  for i in {1..60}; do
    if curl -sf "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"ok"'; then
      log "Server is healthy on port $PORT"
      return
    fi
    sleep 1
  done

  err "Server failed to start. Tail of log:"
  tail -30 /tmp/picoagent-server.log
  exit 1
}

# ============================================================================
# 6. Verify
# ============================================================================
verify() {
  log "Step 6: Verify end-to-end"

  info "Health check:"
  curl -s "http://127.0.0.1:$PORT/health"; echo

  info "pi --list-models:"
  pi --list-models 2>&1 | grep -iE 'qwythos|provider|model' || true

  info "Quick generation test:"
  local resp
  resp=$(curl -s "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"Qwythos","messages":[{"role":"user","content":"What is 7+8? Just the number."}],"max_tokens":32,"temperature":0.6}')
  echo "$resp" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('  ->', d.get('choices',[{}])[0].get('message',{}).get('content','<no content>')[:200])" 2>/dev/null || echo "  (raw) $resp" | head -c 300

  echo
  log "All set. Use pi (Qwythos is the default model):"
  echo "    cd /your/project"
  echo "    pi"
  echo
  echo "  Or override per-run:"
  echo "    pi --model Qwythos"
  echo
  echo "  Server log:  /tmp/picoagent-server.log"
  echo "  Stop server: pkill -F /tmp/picoagent-server.pid"
}

# ============================================================================
# Main
# ============================================================================
main() {
  echo
  echo "============================================================"
  echo "  PicoAgent — local Qwythos 9B + pi coding agent setup"
  echo "============================================================"
  echo

  preflight
  download_model
  build_llama
  install_pi
  register_extension
  set_default_model
  start_server
  verify
}

main "$@"
