Hardware Overview:

  Model Name:	Mac mini
  Model Identifier:	Mac16,11
  Model Number:	Z1JV000FMFN/A
  Chip:	Apple M4 Pro
  Total Number of Cores:	14 (10 Performance and 4 Efficiency)
  Memory:	24 GB
  System Firmware Version:	18000.121.3
  OS Loader Version:	18000.121.3
  Serial Number (system):	HR93P6MJ6D
  Hardware UUID:	924E27BF-3359-5BF1-A6C7-1C68A4E64FD5
  Provisioning UDID:	00006040-000649611EF3801C
  Activation Lock Status:	Enabled

That configuration is quite suitable for MLXServe. The key constraint is the **24 GB unified memory**: it makes ~30B MoE models practical when quantized to 4-bit, but leaves little room for very large context windows or other memory-heavy applications running simultaneously.

For coding, I would now slightly change the model recommendation from the earlier general-purpose `Qwen3-30B-A3B` to **`Qwen3-Coder-30B-A3B-Instruct-4bit`**. There is an MLX conversion specifically optimized for Apple Silicon, and Qwen designed this variant for agentic coding and repository-scale work. 

Your likely setup would therefore be:

```text
Mac mini M4 Pro
14-core CPU
24 GB unified memory
        │
        ▼
    MLXServe
        │
        ▼
Qwen3-Coder-30B-A3B
      4-bit MLX
        │
        ▼
OpenAI-compatible local API
        │
        ├── coding agent
        ├── Claude Code-compatible clients
        ├── OpenCode / Pi / etc.
        └── eventually Augment, if BYO endpoint becomes supported
```

### Why the 30B-A3B model fits unusually well

`30B-A3B` means roughly **30 billion total parameters but only ~3 billion activated for each token**. That's the beauty of the MoE architecture: you retain a much larger model's capacity without executing all 30B parameters for every generated token. Qwen describes the original Qwen3-30B-A3B exactly this way. 

A typical MLX 4-bit version of this class occupies roughly **17 GB for the weights**; for example the MLX Qwen3-Coder conversion is listed at about 17.2 GB. 

That leaves approximately:

```text
24 GB unified memory
− ~17 GB model weights
────────────────────
  ~7 GB remaining
```

That remaining memory has to accommodate macOS, MLX runtime overhead, KV cache, applications, and everything else. So **it fits, but this is near the upper end of what I'd deliberately run on a 24-GB Mac**.

This is why I would *not* recommend a Qwen 32B dense model on this machine. The MoE architecture is much more attractive.

### There's an interesting newer option

Because we're now in August 2026, there are newer Qwen models than the Qwen3 model from the video you originally watched.

For example, MLX Community now provides **Qwen3.5-35B-A3B-4bit**. Its MLX model is about **20.4 GB**, so technically it can fit in 24 GB. 

But I would **not start there**.

With ~20.4 GB consumed by model weights, you'd have only ~3.6 GB before accounting for macOS and KV cache. That's too tight for the comfortable desktop-development environment you want.

So I'd classify the choices roughly like this:

| Model | 24 GB M4 Pro | My verdict |
|---|---:|---|
| Qwen 7–8B 4-bit | 🟢 Easy | Very fast, but noticeably weaker |
| Qwen 14B 4-bit | 🟢 Excellent | Great lightweight model |
| **Qwen3-Coder-30B-A3B 4-bit** | 🟢/🟡 | **Sweet spot** |
| Qwen3-30B-A3B 4-bit | 🟢/🟡 | Excellent general model |
| Qwen3.5-35B-A3B 4-bit | 🟡/🔴 | Fits, but memory too tight |
| ~32B dense | 🔴 | Avoid on 24 GB |
| 70B-class | 🔴 | Wrong machine configuration |

The important nuance is that "fits in RAM" is not the same thing as "pleasant to use." For a development workstation, I'd prefer several gigabytes of headroom.

## I'd actually install two models

Rather than trying to make one model do everything, I think your Mac Mini lends itself nicely to a two-tier local setup:

```text
             MLXServe
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
  Fast model          Smart model

 Qwen ~14B       Qwen3-Coder-30B-A3B
   4-bit                 4-bit
        │                 │
        ▼                 ▼
quick edits          architecture
summaries            refactoring
small scripts        debugging
git messages         agentic coding
docs                 multi-file tasks
```

You wouldn't normally keep both models resident simultaneously. MLXServe can act as the stable API/model-management layer and load what you need. It supports MLX and GGUF models plus OpenAI-, Anthropic- and Ollama-compatible APIs. 

For the **smart coding model**, my starting choice would be:

```text
mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
```

rather than:

```text
Qwen/Qwen3-30B-A3B-MLX-4bit
```

The latter is perfectly valid and has an official Qwen 4-bit MLX conversion, but it is a general-purpose model.  The Coder variant is much closer to your actual objective.

## And this makes MLXServe more interesting than Ollama for you

For this Mac, I'd favor:

**MLXServe → MLX models**

rather than:

**Ollama → GGUF models**

for the main experiment.

MLXServe runs MLX natively and also supports GGUF, so you're not giving up GGUF compatibility. Its current documentation explicitly positions it as an Apple-Silicon-native server exposing OpenAI, Anthropic and Ollama-compatible APIs. 

That gives you a nice separation:

```text
APPLICATIONS
Augment / OpenCode / Claude Code / agents
                 │
                 │ OpenAI / Anthropic API
                 ▼
─────────────────────────────────────────
             MLXServe
─────────────────────────────────────────
                 │
                 │ MLX
                 ▼
         LOCAL MODEL LAYER
       Qwen3-Coder-30B-A3B
─────────────────────────────────────────
              Apple MLX
─────────────────────────────────────────
                 │
                 ▼
          M4 Pro / 24 GB
```

And that architecture is valuable even if Augment Intent never supports local inference directly.

### The big economic point

This is also where your original cost-saving idea becomes realistic.

You don't necessarily need to replace Augment.

Instead:

```text
100 coding tasks
       │
       ├── perhaps 60–80 routine tasks
       │             │
       │             ▼
       │        local Qwen
       │        €0 tokens
       │
       └── perhaps 20–40 difficult tasks
                     │
                     ▼
               Augment Intent
               frontier models
```

Those percentages are deliberately hypothetical—we should measure them from your actual workflow rather than assume them—but that's the experiment I'd run.

If you discover that a local Qwen handles, say, 70% of your everyday repository work adequately, **then Augment becomes the escalation tier rather than the default execution tier**.

That could materially change the economics of your development workflow.

One final thing: you included the machine's serial number, hardware UUID and provisioning UDID above. None of those are necessary for deciding which LLM to run; I'd omit those identifiers when sharing system specs publicly. The useful data here are simply **M4 Pro / 14 cores / 24 GB unified memory**.

**So my recommendation is now quite concrete: install MLXServe on this Mac and make `Qwen3-Coder-30B-A3B-Instruct-4bit` our first benchmark model.** Then we can benchmark it specifically against the kinds of jobs you're currently sending to Augment Intent—code generation, multi-file modification, architectural reasoning, refactoring and agentic repository work—and calculate what proportion can realistically move local.
