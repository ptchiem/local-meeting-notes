# Local meeting notes

Record any meeting on your Mac (Zoom, Google Meet, Webex, Teams, and others) and get an AI transcript and summary. Everything runs on your own computer: no bot joins the call, and no audio or text is sent to a cloud service.

This uses two free, open-source apps:

- [anarlog](https://anarlog.so) records the meeting and writes the transcript and summary.
- [Ollama](https://ollama.com) runs the AI model that writes the summary.

## Requirements

- A Mac with Apple Silicon (M1 or newer). Intel Macs aren't supported.
- macOS 15 or newer.
- Free disk space for the AI model: about 18 GB on Macs with 32 GB or more of memory, and less on smaller Macs.

## Install

Unzip the folder, open Terminal, and run:

```bash
cd ~/Downloads/local-meeting-notes   # or wherever you unzipped it
bash setup.sh
```

The script:

1. Installs Homebrew if you don't have it. It asks first.
2. Installs anarlog and Ollama.
3. Downloads a summary model sized for your Mac's memory:
   | Memory | Model |
   | --- | --- |
   | 32 GB or more | `qwen3.8:27b` |
   | 16–31 GB | `gemma4:12b` |
   | Less than 16 GB | `granite4.2:3b` |
4. Opens anarlog once for its welcome screens, then sets it to transcribe and summarize on your Mac. It backs up anarlog's settings first.

The model download is large. If it's interrupted, run `bash setup.sh` again and it picks up where it left off.

## After the script finishes

1. In anarlog, open **Settings → Transcription** and click to download the **Parakeet Batch** model. You only do this once.
2. Open the **Welcome to Anarlog** note and click **Join & record** to try a demo meeting.
3. When macOS asks, allow **Microphone** and **System Audio Recording**. anarlog needs both to hear you and the other people on the call.

For real meetings, click **Record** in a new note and join your call as usual. Type a few rough notes during the meeting; the summary builds on them.

## Recording etiquette

Nobody in the meeting is notified that you're recording. Tell people you're taking AI notes. Some places, including California, require everyone's consent to record a call.

## Keeping it private

Before a sensitive meeting, check both of these in anarlog:

- **Settings → Transcription → Model being used** shows a Soniqo model.
- **Settings → Intelligence → Model being used** shows an Ollama model.

Anything labeled Anarlog, Pro (Cloud), or a named service like Deepgram or OpenAI sends your meeting off your Mac. Also avoid web search in anarlog's chat, which sends your question to an online service.

## Options

```bash
MODEL=gemma4:12b bash setup.sh   # pick a specific Ollama model
SKIP_SETTINGS=1 bash setup.sh    # install everything, but set anarlog's options yourself
```

If the script can't apply anarlog's settings (for example, after an anarlog update changes how they're stored), it prints the menu steps to set them by hand.

## Uninstall

```bash
brew uninstall --cask anarlog ollama-app
rm -rf ~/.ollama/models   # deletes downloaded AI models
```
