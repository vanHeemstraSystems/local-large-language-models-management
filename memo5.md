Yes. I found something much better than the tunnel workaround: the open-source community has already implemented a fully local Warp agent.

Best match: man-brain/warp → local-agent

man-brain/warp local-agent fork on GitHub⁠￼

This is a fork of the now-open-source Warp client specifically modified to remove Warp’s cloud AI dependency. Its README says the client does not contact Warp’s servers for AI, requires no Warp authentication, runs the agent loop locally, and talks directly to an OpenAI-compatible endpoint.

That means our architecture becomes exactly what we wanted:

┌──────────────────────────────────────┐│ Mac mini M4 Pro ││ ││ Warp local-agent ││ │ ││ │ OpenAI API ││ ▼ ││ [http://127.0.0.1:11234/v1](http://127.0.0.1:11234/v1) ││ │ ││ ▼ ││ MLXServe ││ │ ││ ▼ ││ Qwen3-Coder-30B-A3B-Instruct-4bit ││ │└──────────────────────────────────────┘NO CLOUD

And this isn’t just a proposal. The author says he uses the implementation day-to-day, rebases it regularly against Warp, and implemented precisely Warp’s proposed option of a lightweight local harness speaking Warp’s client protocol.

It explicitly supports our setup

The fork tells users to configure:

Settings→ AI→ Custom inference / model providers

with something such as:

Base URL:[http://localhost:11234/v1](http://localhost:11234/v1)API key:<none, assuming MLXServe doesn't require one>Model:Qwen3-Coder-30B-A3B-Instruct-4bit

Crucially, this fork deliberately allows loopback and private-network addresses over plain HTTP.

So MLXServe can stay exactly where it is.

No Cloudflare.

No ngrok.

No public DNS.

No GGUF conversion.

No Ollama.

No Qwen model-format conversion.

There’s an even more packaged implementation: OpenWarp

I also found another community project that has taken this concept further:

sasuke39/open-warp on GitHub⁠￼

It describes itself explicitly as:

“Run your own LLM inside Warp.”

Rather than merely changing the custom endpoint, OpenWarp patches the Warp client to route its AI protocol to a local Go adapter. That adapter translates Warp’s protobuf protocol into OpenAI-compatible requests, handles local tools, and streams the result back into Warp.

Even better for your Mac, it supplies a separate:

WarpLocal.app

which can coexist with the normal Warp installation.

Its workflow is essentially:

WarpLocal.app│▼local Go adapter││ OpenAI compatible▼MLXServe│▼Qwen3

And its documentation explicitly lists compatibility with:

- Ollama
- LM Studio
- vLLM
- DeepSeek
- OpenRouter
- any OpenAI-compatible endpoint

That last category is where our MLXServe belongs.

There’s actually a small ecosystem forming

The most recent Warp discussion is particularly interesting. On August 17, 2026, a community contributor reported that there are now “nearly a dozen forks” implementing local agents in Warp, specifically mentioning zerx-lab/zap, man-brain/warp’s local-agent, and Local-Warp.

zerx-lab/zap on GitHub⁠￼

That contributor reports successfully running Qwen inside Warp’s own model picker, including Warp skills. They specifically describe getting a Claude Code skill from ~/.claude/skills to run on a Qwen model through the local path.

That’s remarkably close to our exact requirement.

Why we need the fork rather than ordinary Warp

This also confirms our previous diagnosis. Official Warp still rejects localhost/private inference because inference is routed through Warp’s backend. The open issue requesting direct localhost, 127.0.0.1, ::1, and private-network support remains open.

The Warp team itself says fully client-side local model support remains a separate future direction.

So the community has effectively implemented the missing Warp feature before upstream Warp has shipped it.

What I recommend for our Local LLM stack

I would start with man-brain/warp:local-agent, rather than OpenWarp.

There’s an architectural reason.

The official Warp client itself is now open source: most of it is AGPLv3, while WarpUI components are MIT. The proprietary pieces are primarily Warp’s server/backend and Oz orchestration.

The local-agent fork replaces exactly that missing cloud-side agent functionality locally.

Therefore our stack becomes:

```
                LOCAL LLM STACK
             ┌─────────────────┐
             │ Warp Local      │
             │ Agent           │
             └────────┬────────┘
                      │
               agent/tool loop
                      │
                      ▼
             OpenAI-compatible
                   API
                      │
                      ▼
          ┌─────────────────────┐
          │ MLXServe            │
          │ 127.0.0.1:11234     │
          └──────────┬──────────┘
                     │
                     ▼
         ┌────────────────────────┐
         │ Qwen3-Coder 30B A3B    │
         │ MLX / 4-bit            │
         └────────────┬───────────┘
                      │
                      ▼
              Apple MLX / Metal
                      │
                      ▼
                M4 Pro / 24 GB
```

Everything inside the box is local.

And this answers your original Qwen3 file-format question rather elegantly: Warp doesn’t need to understand Qwen’s model files.

MLX does:

Qwen MLX/Safetensors↓MLX↓MLXServe↓OpenAI-compatible JSON↓Warp local-agent

So I would not alter the working Qwen3-Coder model at all.

One further advantage: upstream Warp itself can be built locally with ./script/bootstrap, ./script/run, and ./script/presubmit. The local-agent fork similarly documents producing a native macOS WarpOss.app/DMG using ./script/bundle --channel oss.

This is the route I’d take. We should treat man-brain/warp:local-agent as an upstream community reference, bring the relevant implementation into our local-large-language-models-management strategy, build WarpOss.app on the Mac mini, point it straight at the already-working MLXServe localhost:11234, and test Qwen3 tool calling end-to-end. If that works—as the existing Qwen reports strongly suggest—we have effectively achieved the goal: Warp IDE + Warp Agent + Qwen3-Coder + MLXServe + M4 Pro, with inference staying entirely on the Mac.