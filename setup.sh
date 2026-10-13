#!/usr/bin/env bash
#
# Sets up anarlog + Ollama for fully local meeting notes on an Apple Silicon Mac:
# on-device transcription (Soniqo Parakeet Batch) and on-device summaries (Ollama).
#
# Usage:   ./setup.sh
# Options: MODEL=<ollama-model> ./setup.sh   override the automatic model choice
#          SKIP_SETTINGS=1 ./setup.sh        install everything but leave anarlog settings alone

set -euo pipefail

STT_PROVIDER="soniqo"
STT_MODEL="soniqo-parakeet-batch"
LLM_PROVIDER="ollama"
LLM_REASONING_EFFORT="default"

ANARLOG_DB="${ANARLOG_DB:-$HOME/Library/Application Support/anarlog/app.db}"
OLLAMA_URL="http://localhost:11434"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  \033[33mWarning:\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

is_interactive() { [[ -t 0 ]]; }

pause() {
  if is_interactive; then
    read -r -p "  $1 " _
  fi
}

check_mac() {
  bold "Checking this Mac"
  [[ "$(uname -s)" == "Darwin" ]] || die "This script only supports macOS."

  [[ "$(uname -m)" == "arm64" ]] ||
    die "On-device transcription in anarlog needs an Apple Silicon Mac (M1 or newer). Intel Macs aren't supported."

  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 15 )) || die "anarlog needs macOS 15 or newer. This Mac has $(sw_vers -productVersion)."

  RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  info "Apple Silicon, macOS $(sw_vers -productVersion), ${RAM_GB} GB memory"
}

choose_model() {
  if [[ -n "${MODEL:-}" ]]; then
    info "Using model from MODEL: $MODEL"
  elif (( RAM_GB >= 32 )); then
    MODEL="gpt-oss:20b"
  elif (( RAM_GB >= 16 )); then
    MODEL="gemma4:12b"
  else
    MODEL="granite4.2:3b"
  fi

  [[ "$MODEL" =~ ^[A-Za-z0-9._:/-]+$ ]] || die "Invalid model name: $MODEL"
  info "Summary model: $MODEL"
}

ensure_homebrew() {
  bold "Checking Homebrew"
  if ! command -v brew >/dev/null 2>&1 && [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  if command -v brew >/dev/null 2>&1; then
    info "Homebrew is installed."
    return
  fi

  is_interactive || die "Homebrew is required. Install it from https://brew.sh and run this script again."
  info "Homebrew (the standard Mac package manager) is needed to install the apps."
  pause "Press Enter to install it, or Ctrl+C to cancel."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

install_apps() {
  bold "Installing apps"
  if [[ -d /Applications/Anarlog.app ]]; then
    info "anarlog is already installed."
  else
    brew install --cask anarlog
  fi

  if command -v ollama >/dev/null 2>&1 || [[ -d /Applications/Ollama.app ]]; then
    info "Ollama is already installed."
  else
    brew install --cask ollama-app
  fi
}

ollama_running() { curl -fsS -m 2 "$OLLAMA_URL/api/version" >/dev/null 2>&1; }

start_ollama() {
  bold "Starting Ollama"
  if ! ollama_running; then
    if [[ -d /Applications/Ollama.app ]]; then
      open -a Ollama
    else
      (ollama serve >/dev/null 2>&1 &)
    fi
  fi

  for _ in $(seq 1 60); do
    ollama_running && { info "Ollama is running."; return; }
    sleep 1
  done
  die "Ollama didn't start. Open the Ollama app manually and run this script again."
}

pull_model() {
  bold "Downloading $MODEL"
  if ollama list | awk 'NR>1 {print $1}' | grep -qx "$MODEL"; then
    info "Already downloaded."
    return
  fi
  info "This is a large download and can take a while. If it's interrupted, run the script again to resume."
  ollama pull "$MODEL"
}

anarlog_running() { pgrep -x anarlog >/dev/null 2>&1; }

quit_anarlog() {
  anarlog_running || return 0
  osascript -e 'tell application "Anarlog" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    anarlog_running || return 0
    sleep 1
  done
  return 1
}

sql_json_string() { printf "'\"%s\"'" "$1"; }

write_settings() {
  [[ -f "$ANARLOG_DB" ]] || { warn "anarlog's settings database wasn't found."; return 1; }

  local columns
  columns="$(sqlite3 "$ANARLOG_DB" "select group_concat(name) from pragma_table_info('app_settings')" 2>/dev/null || true)"
  if [[ ",$columns," != *",id,"* || ",$columns," != *",value_json,"* ]]; then
    warn "anarlog's settings format has changed since this script was written."
    return 1
  fi

  local backup="${ANARLOG_DB}.backup-$(date +%Y%m%d-%H%M%S)"
  sqlite3 "$ANARLOG_DB" ".backup '$backup'" || { warn "Couldn't back up anarlog's database."; return 1; }
  info "Backed up anarlog's database to: $backup"

  sqlite3 "$ANARLOG_DB" <<SQL || { warn "Couldn't write settings."; return 1; }
INSERT INTO app_settings (id, value_json) VALUES
  ('current_stt_provider',         $(sql_json_string "$STT_PROVIDER")),
  ('current_stt_model',            $(sql_json_string "$STT_MODEL")),
  ('current_llm_provider',         $(sql_json_string "$LLM_PROVIDER")),
  ('current_llm_model',            $(sql_json_string "$MODEL")),
  ('current_llm_reasoning_effort', $(sql_json_string "$LLM_REASONING_EFFORT"))
ON CONFLICT(id) DO UPDATE SET
  value_json = excluded.value_json,
  updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now');
SQL

  local applied
  applied="$(sqlite3 "$ANARLOG_DB" "select value_json from app_settings where id in ('current_stt_model','current_llm_model') order by id")"
  [[ "$applied" == "\"$MODEL\""$'\n'"\"$STT_MODEL\"" ]] || { warn "Settings didn't save as expected."; return 1; }
}

print_manual_steps() {
  cat <<EOF

  Set these two options in anarlog yourself:
    1. Settings → Transcription: choose Soniqo, then Parakeet Batch. Click to download it,
       and make sure "Model being used" shows it.
    2. Settings → Intelligence → Configure Providers → Ollama. Under "Model being used",
       select $MODEL.
EOF
}

configure_anarlog() {
  bold "Configuring anarlog"
  if [[ -n "${SKIP_SETTINGS:-}" ]]; then
    info "SKIP_SETTINGS is set, so anarlog's settings were left alone."
    print_manual_steps
    return
  fi

  if [[ ! -f "$ANARLOG_DB" ]] && is_interactive; then
    info "Opening anarlog for its first-run setup."
    open -a Anarlog
    info "Finish the welcome screens. Skip any sign-in or AI choices; this script sets those next."
    pause "Press Enter when you reach the main anarlog window."
  fi

  if ! quit_anarlog; then
    warn "anarlog didn't quit, so its settings weren't changed."
    print_manual_steps
    return
  fi

  if write_settings; then
    info "Transcription: Soniqo Parakeet Batch (on this Mac)"
    info "Summaries: Ollama $MODEL (on this Mac)"
  else
    print_manual_steps
  fi
  open -a Anarlog
}

print_next_steps() {
  bold "Almost done"
  cat <<EOF
  1. In anarlog, open Settings → Transcription and click to download the Parakeet Batch
     model (one-time).
  2. Open the "Welcome to Anarlog" note and click "Join & record" to try the demo.
     Allow Microphone and System Audio Recording when macOS asks.
  3. Before a sensitive meeting, check that Settings → Transcription and
     Settings → Intelligence both still point to the on-device models above.

  Everything stays on this Mac. Nobody in a meeting is notified that you're recording,
  so tell people you're taking AI notes. Some places require everyone's consent.
EOF
}

main() {
  check_mac
  choose_model
  ensure_homebrew
  install_apps
  start_ollama
  pull_model
  configure_anarlog
  print_next_steps
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
