# Memo 18: Memo: Local LLM Hardware Tiers and Deployment Strategy

Status: Proposed  
Repository: Local LLMs Management  
Purpose: Evaluate local AI hardware tiers, model capabilities, and the trade-offs between local inference and cloud subscriptions.

## 1. Executive Summary

Local AI hardware can be divided into three broad tiers:

### 1. Entry-level: 
Approximately 8B-parameter models for private, straightforward conversational tasks.

### 2. Mid-range: 
Quantized models in the 27B-parameter class and beyond, suitable for coding agents and practical development workflows.

### 3. High-end: 
Systems with approximately 128GB of unified memory, capable of hosting models in the 70B–120B parameter range, depending on architecture, quantization, and runtime overhead.

The most important lesson is that model capacity, inference speed, and practical agent capability are different things. A model fitting into memory does not guarantee acceptable performance, and a faster model does not necessarily produce better results.

For Local LLMs Management, the recommended strategy is to continue developing a hybrid workflow that combines local inference with subscription-based cloud models. Hardware purchases should follow demonstrated workload requirements rather than theoretical maximum model sizes.

## 2. Three Hardware Tiers

The following estimates are taken from the source material provided by Tim. They are indicative figures, not independently verified current market prices. Hardware prices, model performance, and available products change over time.

2.1 Entry-level local AI

Representative hardware

* Windows PC with a used NVIDIA RTX 3060 and 12GB VRAM.
* Base Mac mini with Apple silicon and unified memory.

Indicative costs

* RTX 3060 GPU: $300–$400.
* Base Mac mini: approximately $800–$900.
* Complete PC built from scratch: approximately $1,000 at the low end.

Typical workload

* Approximately 8B-parameter models.
* Summarization and drafting.
* Document creation and review.
* Private conversational AI that does not need to send data to a cloud inference provider.

The source estimates approximately 40–50 tokens per second for its RTX 3060 example. Actual performance depends on the model, quantization, context length, runtime, and workload.

Limitations

Entry-level systems are best suited to simple inference. They can support tools and agent workflows in principle, but memory constraints and model capability may limit more demanding software-engineering tasks.

2.2 Mid-range local AI

Representative hardware

* NVIDIA RTX 3090 with 24GB VRAM.
* Mac mini M4 Pro with 48GB unified memory.

Indicative costs

* RTX 3090 GPU: approximately $1,000–$1,300, according to the source.
* Mac mini M4 Pro with 48GB unified memory: approximately $2,000 or more, according to the source.

These figures should not be treated as current purchasing recommendations. A GPU price is not the same as the cost of a complete PC.

Typical workload

* Quantized models around 27B parameters, subject to memory requirements.
* Coding agents and repository analysis.
* Iterative code generation and refactoring.
* Local tool orchestration and structured engineering workflows.

An RTX 3090 can offer high inference throughput when the model fits in VRAM. Apple silicon provides a larger unified-memory pool in the example above, but inference speed depends on memory bandwidth, model architecture, and software optimization.

Relevance to Local LLMs Management

This tier is particularly relevant because it supports experimentation with autonomous coding workflows, local model serving, and selective delegation to cloud models.

However, agent effectiveness also depends on context management, tool execution, error recovery, and model reliability. Hardware alone does not solve these problems.

2.3 High-end local AI

Representative hardware mentioned in the source

* AMD Strix Halo mini PC.
* NVIDIA DGX Spark.
* High-memory Apple Mac Studio configurations.

The source discusses systems costing approximately $3,000–$5,000 and configurations with around 128GB of memory. These product names, specifications, and prices must be checked against the actual configuration available before any purchasing decision.

Typical workload

* Quantized models in the 70B–120B parameter range, depending on memory requirements.
* More demanding reasoning and coding tasks.
* Larger local inference workloads.
* Greater independence from external inference providers.

Important distinction: capacity versus speed

A 120B model may fit in memory but run considerably slower than a smaller model. Memory bandwidth, quantization, context length, runtime overhead, and the model architecture all influence throughput.

Tim reports approximately 40 tokens per second for a 120B model on his DGX Spark, compared with approximately 60–90 tokens per second for 35B–70B models. These are source-reported measurements, not universal benchmarks.

The practical implication is to benchmark models on the actual target hardware rather than selecting a system solely on its advertised memory capacity.

3. Assessment of the Existing Local Setup

The current Local LLMs Management environment uses:

* Computer: Mac mini M4 Pro with 24GB unified memory.
* Inference runtime: MLXServe.
* Model: Qwen3-Coder-30B-A3B-Instruct, 4-bit quantization.
* Model serving: Local endpoint at 127.0.0.1:11234.
* Model directory: ~/.mlx-serve/models.
* Context configuration: 8192 tokens.
* Generation configuration: Maximum 1024 output tokens and 4-bit KV-cache quantization.
* Development clients: OpenCode and Warp.

This setup does not fit neatly into a simple parameter-count tier. Qwen3-Coder-30B-A3B is a mixture-of-experts model: although it contains approximately 30B total parameters, only a subset is activated for each token. Its memory requirements are determined primarily by the model’s stored weights, runtime allocations, and context-related memory, not merely by the number of active parameters.

The current 24GB system is therefore a constrained but useful local development environment. It offers a practical platform for evaluating local coding agents without immediately investing in a high-memory workstation.

Existing constraint: context capacity

The environment has previously reported:

Prompt exceeds maximum context length: 1230 requested, 870 available

This illustrates why nominal context settings must be evaluated alongside memory availability and runtime behavior. Increasing the configured context length does not guarantee that the complete prompt can be processed.

The implementation should measure effective context capacity, memory pressure, and failure rates rather than assuming that the configured 8192-token context is always available in full.

4. Recommended Local/Cloud Model Strategy

Local LLMs Management should implement a workload-based routing strategy.

Workload	Preferred execution path
Routine explanations and short drafts	Local Qwen model
Simple code changes and small refactors	Local Qwen model, with verification
Repository-wide investigation	Evaluate local capacity; escalate when context or quality is insufficient
Complex debugging and architectural decisions	Cloud model when the local model cannot meet the quality threshold
Large or difficult multi-step coding tasks	Cloud coding model, with local fallback where practical
Private documents and source material requiring local processing	Local model, subject to the configured privacy policy
Tests, builds, formatting, and static analysis	Local development tools

The routing decision should be based on task complexity, required context, available memory, expected quality, latency, and subscription limits.

A cloud model should not automatically be selected for every difficult task. Conversely, a local model should not be forced to continue when repeated failures indicate that escalation would be more efficient.

Subscription economics

A subscription-based cloud service can be more economical than purchasing and maintaining high-end hardware, especially for occasional demanding tasks.

Local inference may be attractive when usage is frequent, privacy is important, offline operation is required, or predictable infrastructure costs matter.

The total cost comparison should account for:

* Hardware acquisition and depreciation.
* Electricity and cooling.
* Maintenance and setup time.
* Cloud subscription fees and usage limits.
* Time spent correcting model errors.
* The value of data remaining local.

The source’s comparison with $20, $40, or $60 monthly cloud services is illustrative rather than a verified current price list. Subscription prices, model access, and usage limits should be checked before making a financial decision.

5. Implementation Recommendations

Phase 1 — Establish a baseline

Record the performance of the existing Mac mini M4 Pro and Qwen3-Coder configuration.

Measure:

* Model loading time.
* Prompt-processing throughput.
* Generation throughput in tokens per second.
* Peak memory usage.
* Maximum reliable context length.
* Time to complete representative coding tasks.
* Tool-call success rate.
* Task completion rate and required human corrections.

Use repeatable tasks and consistent test conditions so that future hardware and model comparisons are meaningful.

Phase 2 — Improve local inference reliability

Review the current MLXServe configuration, context management, and KV-cache settings.

Prioritize:

* Preventing context overflow.
* Managing memory pressure.
* Reusing model instances where appropriate.
* Capturing structured errors and latency measurements.
* Making failed tool calls and incomplete responses visible.
* Ensuring that generated code is tested before acceptance.

Do not purchase new hardware merely to compensate for avoidable configuration or orchestration problems.

Phase 3 — Integrate cloud escalation

Maintain the local Qwen model as the default for suitable tasks and use a subscription-based cloud coding model for work that exceeds local capability.

The OpenCode Go subscription with Kimi should be evaluated as a possible cloud execution path, subject to its current model availability, usage limits, and integration behavior.

Keep provider-specific configuration separate from task-routing policy. This allows the cloud provider or model to change without redesigning the entire workflow.

Phase 4 — Evaluate hardware upgrades only when justified

Consider a higher-memory Mac or dedicated GPU workstation when collected measurements show that the existing system is consistently limited by:

* Insufficient memory.
* Inadequate context capacity.
* Unacceptable inference latency.
* Model-quality limitations that could be addressed by a larger local model.
* A sufficiently high volume of cloud inference to justify local infrastructure.

Benchmark the complete workflow, not just tokens per second. For a coding agent, tool execution, context preparation, testing, and recovery can contribute substantially to total task time.

6. Architectural Principle

Local LLMs Management should treat hardware, inference engines, models, and orchestration as separate, replaceable components.

A useful conceptual architecture is:

1. Task intake: Receive the user request and relevant repository context.
2. Task assessment: Estimate complexity, privacy requirements, context size, and quality expectations.
3. Model selection: Select local Qwen or an approved cloud model.
4. Execution: Generate responses and invoke authorized tools.
5. Validation: Run applicable tests and inspect results.
6. Escalation: Retry, simplify, or route the task to a more capable model when justified.
7. Human review: Require approval for consequential changes and publication.
8. Telemetry: Record performance, costs, failures, and outcomes.

This architecture makes the system less dependent on a particular computer or model and supports future integration of additional local and cloud providers.

7. Security and Privacy Considerations

Local execution can reduce the need to transmit sensitive content to external inference services, but it does not automatically guarantee complete privacy.

The implementation should explicitly control:

* Which prompts and files may be sent to cloud providers.
* Which tools the model may invoke.
* Whether commands can modify files or execute arbitrary processes.
* Which credentials are available to the coding agent.
* What prompts, source code, and tool results are retained in logs.
* Which operations require human approval.

Cloud escalation must respect repository confidentiality, organizational policies, and user consent.

8. Decision

Recommendation: retain the existing Mac mini M4 Pro as the local inference baseline and optimize the hybrid workflow before purchasing additional hardware.

The current machine already supports experimentation with a quantized coding model and local serving. The next meaningful improvement is to measure end-to-end coding-agent performance, establish reliable escalation thresholds, and compare the total cost of local execution with the existing cloud subscription.

High-memory hardware should remain a future option, justified by measured workloads rather than theoretical model capacity.

9. References

Source material

* Tim, personal correspondence on three tiers of local AI hardware, reproduced in the originating discussion. Hardware prices and performance figures in this memo are attributed to that correspondence and have not been independently benchmarked.
* MLX: https://github.com/ml-explore/mlx
* MLX LM: https://github.com/ml-explore/mlx-lm
* OpenCode documentation: https://opencode.ai/docs/
* OpenCode Go documentation: https://dev.opencode.ai/docs/go/

Model and deployment verification

Before changing the implementation, verify the exact model repository, model revision, quantization, runtime version, and configuration used in the current environment. Re-run local benchmarks whenever the model, inference engine, or hardware changes.

⸻

Outcome: Local LLMs Management should optimize for reliable, cost-effective engineering outcomes—not the largest model that can theoretically fit into memory.
