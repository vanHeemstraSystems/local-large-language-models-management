# Prompt:

I watched https://www.youtube.com/watch?v=XVwMi_UOfsQ and it recommends https://huggingface.co/Qwen/Qwen3-30B-A3B for local LLM on my Mac Mini M4 Pro. Please elaborate how this would save me money expenditure on the use of Augment Code Intent.

# Response:

Yes. The interesting part is not merely “run Qwen locally instead of paying for an API.” For your setup, the potentially valuable architecture is:

Intent → OpenCode → local Qwen3-30B-A3B → your M4 Pro

rather than:

Intent → Auggie/cloud model → metered LLM inference

And Augment explicitly says OpenCode support in Intent means you can use local models with Intent. 

Why Qwen3-30B-A3B is interesting on Apple Silicon

Qwen3-30B-A3B on Hugging Face⁠￼ is a Mixture-of-Experts model. Although it contains 30.5B parameters, only 3.3B parameters are activated per token. It has 128 experts, activates 8 at a time, and has a native 32K context window, extendable to 131K with YaRN. Qwen specifically highlights coding, reasoning, tool use and agentic workloads. 

That distinction is important:

30B model capacity, but roughly 3B active parameters during inference.

You still need enough unified memory to hold the quantized model, KV cache and runtime overhead, so it isn’t equivalent to storing a 3B model. But the computational load per generated token is substantially lower than a dense 30B model.

Qwen officially lists MLX-LM, llama.cpp, Ollama and LM Studio among the supported ways of running Qwen3 locally. 

For your Mac Mini, I’d lean toward MLX for maximum Apple-Silicon efficiency, or Ollama if ease of integration is the priority.

⸻

The really interesting bit: Augment Intent

This is where your observation becomes financially useful.

Intent supports BYOA — Bring Your Own Agent — including:

Auggie | Claude Code | Codex | OpenCode

And Augment states that OpenCode support allows local models to be used with Intent. 

So you can potentially construct this:

                    AUGMENT INTENT
                         │
                 Living Specification
                         │
              ┌──────────┴──────────┐
              │                     │
          Coordinator            Verifier
              │                     │
              └──────────┬──────────┘
                         │
                     OpenCode
                         │
                OpenAI-compatible API
                         │
                ┌────────▼─────────┐
                │   Mac Mini M4    │
                │       Pro        │
                │                  │
                │ Qwen3-30B-A3B    │
                │ MLX / Ollama     │
                └──────────────────┘

Instead of paying Augment for every model inference, your Mac performs that computation.

And that distinction matters increasingly because Augment’s current pricing has changed again.

Augment’s current economics

As of today, Augment’s current public Business pricing is $100/month, including $100 of pooled usage. Usage includes LLM inference at the provider’s public API price plus a 40% service fee on LLM usage; usage beyond the included $100 is topped up pay-as-you-go. 

Current Augment Code pricing⁠￼

So imagine a workload that would otherwise consume:

$100 cloud LLM inference
+ $40 Augment service fee
────────────────────────
$140 usage

If the same inference is performed by local Qwen, the marginal inference bill is essentially:

cloud LLM cost          $0
Augment LLM surcharge   $0
electricity             small
Mac depreciation        already sunk

You already own the expensive part: the Mac.

⸻

But don’t throw Augment away

This is the distinction I think matters most.

The valuable thing about Intent isn’t necessarily the LLM.

It’s the orchestration.

Intent gives you things such as:

living specification
        ↓
task decomposition
        ↓
specialist agents
        ↓
isolated git worktrees
        ↓
parallel implementation
        ↓
verification
        ↓
integration

Augment describes BYOA as allowing you to retain the spec workflow, orchestration, Git worktree isolation and resumable sessions while bringing your own execution agent. The paid Context Engine is a separate consideration. 

That suggests a much more interesting cost optimization than simply cancelling Augment.

Use expensive intelligence selectively

I’d eventually aim for something like:

                         INTENT
                           │
                ┌──────────┴──────────┐
                │                     │
          ROUTINE WORK            HARD WORK
                │                     │
          OpenCode/Qwen          premium model
                │                     │
            LOCAL                  CLOUD
                │                     │
              €≈0                 €€€€

Examples:

Task	Model
Read files	Qwen local
Search code	Qwen local
Generate boilerplate	Qwen local
Write tests	Qwen local
Documentation	Qwen local
Straightforward refactoring	Qwen local
YAML/Kubernetes manifests	Qwen local
Routine Python	Qwen local
First-pass code review	Qwen local
Architectural reasoning	premium cloud model
Difficult debugging	premium cloud model
Security-sensitive reasoning	premium cloud model
Final verification of major change	premium cloud model

That could push a large percentage of your token-heavy grunt work onto hardware you’ve already paid for.

⸻

There’s another saving: context

Coding agents can consume surprisingly large amounts of tokens because the expensive operation isn’t always generating 50 lines of code.

It’s repeatedly doing this:

read repository
     ↓
understand files
     ↓
read dependencies
     ↓
reason
     ↓
edit
     ↓
run tests
     ↓
inspect error
     ↓
read more code
     ↓
reason again

An agent might generate only 2,000 output tokens while processing tens or hundreds of thousands of input tokens over a task.

With a cloud model, all that repeated context contributes to metered inference.

With Qwen running locally:

500K tokens processed
         │
         ▼
   Mac Mini GPU
         │
         ▼
marginal token charge = €0

That makes local models particularly attractive for agentic coding, not just chat.

⸻

One caution: Qwen ≠ Claude/GPT at everything

I wouldn’t start by saying:

“Qwen replaces every model inside Intent.”

Instead:

Qwen becomes the default local worker.

Premium models become escalation targets.

That creates a hierarchy:

Tier 0
Deterministic tools
git / grep / tests / compiler
              │
              ▼
Tier 1
Qwen3-30B-A3B
LOCAL
              │
        problem unresolved?
              ▼
Tier 2
strong cloud coding model
              │
        still unresolved?
              ▼
Tier 3
top reasoning model

That is potentially much more economical than sending everything immediately to the most expensive model.

⸻

Why your Mac Mini is especially suitable

Your M4 Pro isn’t just your workstation in this architecture.

It becomes a small private inference server.

You could expose Qwen through an OpenAI-compatible endpoint:

http://localhost:11434

or conceptually:

Mac Mini M4 Pro
│
├── Qwen3-30B-A3B
│
├── MLX / Ollama
│
├── OpenAI-compatible endpoint
│
└── OpenCode
        │
        ▼
     Intent

Qwen itself documents OpenAI-compatible serving options and local runtimes. 

That also gives you an architecture independent of Intent:

                 Local LLM Service
                        │
                Qwen3-30B-A3B
                        │
      ┌──────────┬──────┼──────────┐
      ▼          ▼      ▼          ▼
   OpenCode    scripts   MCP      agents
      │
      ▼
   Intent

Now Intent is a consumer of your local AI infrastructure rather than the owner of your inference layer.

That is a much healthier architectural boundary.

⸻

What I’d do first

I wouldn’t change your Augment subscription yet.

Run an experiment:

Intent + OpenCode + Qwen3-30B-A3B locally, while retaining your current cloud models.

Then measure for perhaps two weeks:

                 ALL INTENT TASKS
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
     Qwen succeeds              Qwen fails
          │                         │
       LOCAL                     CLOUD
          │                         │
        €≈0                    metered cost

If Qwen handles, say, 70–80% of routine agent work, the economic argument becomes compelling. More importantly, you’ll have empirical data from your repositories and your coding style, rather than benchmarks.

The end state I find most attractive is therefore not “replace Augment with Qwen.” It’s “retain Intent as the orchestration/control plane, while moving commodity inference onto the Mac Mini and buying frontier intelligence only when it adds value.”

That turns your Mac Mini M4 Pro into a genuine local LLM execution platform.
