# Prompt

Would MLXServe (https://mlxserve.com) be a good candidate to install on my Mac Mini M4 PRO to use with my desktop Augment Code Intent application?

# Response

Yes—MLXServe looks like a strong serving layer for your Mac Mini M4 Pro, but there’s one important caveat: I can verify that MLXServe exposes the right local APIs; I cannot find evidence that Augment Code Intent currently lets its desktop app point directly at an arbitrary OpenAI-compatible endpoint.

MLXServe itself is a very good fit for the hardware. It is Apple-Silicon-native, supports MLX and GGUF models, binds locally by default, and exposes both OpenAI-compatible /v1/chat/completions and Anthropic-compatible /v1/messages APIs. It specifically targets coding-agent workloads, including streaming and tool calling. 

So architecturally, what you want is:
```
Mac Mini M4 Pro
│
├── MLXServe
│     │
│     └── Qwen / other coding model
│           ↓
│     http://127.0.0.1:11234
│
└── Augment Code Intent
          │
          ├── desired: OpenAI-compatible local endpoint
          │
          └── fallback: Augment cloud models
```
Where MLXServe is especially attractive

Compared with simply running mlx-lm yourself, MLXServe provides exactly the abstraction I would want for your local-LLM setup: model management plus a stable API in front of MLX. It also supports Ollama-compatible APIs, OpenAI Chat Completions/Responses and Anthropic Messages. 

That means you’re not coupling your local-model experiment to Augment:
```
                 ┌─ Augment (if supported)
                 │
                 ├─ Claude Code
                 │
MLXServe ────────┼─ Continue
                 │
                 ├─ OpenCode
                 │
                 └─ your own Open Engineering agents
```
Claude Code, for example, is explicitly supported simply by redirecting ANTHROPIC_BASE_URL to MLXServe. 

The Augment problem

This is the part I would investigate before changing anything about your Augment subscription.

Augment clearly supports multiple models inside its own service—for example, it made GPT-5.4 available across Intent, Auggie CLI and IDE extensions—but I couldn’t find current official documentation saying:

Configure Augment Intent with base_url=http://localhost:11234/v1.

There are also community questions specifically asking Augment for self-hosted/BYOK/local-model support, which suggests this hasn’t historically been a normal supported configuration. 

So I would distinguish two questions:

| Question | Assessment |
| —- | —- |
| Is MLXServe good for your M4 Pro? | Yes, very promising |
| Can it serve Qwen locally? | Yes |
| OpenAI-compatible API? | Yes |
| Anthropic-compatible API? | Yes |
| Good foundation for local coding agents? | Yes |
| Can Augment Intent directly consume it? | Not yet established |
| Will it therefore immediately reduce your Augment bill? | Not necessarily |

There is nevertheless a compelling strategy here. Instead of thinking “replace Augment with MLXServe,” I’d think:

Local-first, Augment-for-hard-problems.

For example:
```
                 Coding task
                     │
                     ▼
              Local coding agent
                     │
             ┌───────┴────────┐
             │                │
          routine           difficult
             │                │
             ▼                ▼
       MLXServe/Qwen      Augment Intent
        $0/token          paid frontier
             │                │
             └───────┬────────┘
                     ▼
                    Git
```
That’s potentially much more valuable than trying to force Augment itself to use MLXServe. A recent study of local/cloud splitting for coding agents found substantial cloud-token reductions from techniques such as local routing and prompt compression, although its exact numbers shouldn’t be assumed to translate directly to Augment. 

What I’d do on your Mac Mini

I would absolutely install MLXServe and treat it as the local LLM runtime/API layer for the Local LLMs project.

## MLXServe⁠￼

Then we should benchmark perhaps three coding models on your actual M4 Pro against a small representative set of your Open Engineering tasks. That will tell us much more than generic model benchmarks.

The next question I suggest we answer is therefore:

“What is the best local coding model to run under MLXServe on my particular M4 Pro, and how much of my current Augment Intent workload could realistically be moved to it?”

For that, the one hardware detail I need is your Mac Mini’s unified-memory size—24 GB, 48 GB, 64 GB, or another configuration. That determines whether we should be looking around 14B, 30B MoE, 32B, or larger models.
