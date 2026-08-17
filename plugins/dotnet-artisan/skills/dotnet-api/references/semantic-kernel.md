# Semantic Kernel

Microsoft Semantic Kernel for AI and LLM orchestration in .NET applications. Covers kernel setup and configuration, plugin/function calling, prompt templates with Handlebars and Liquid syntax, memory and vector store integration, planners, the agents framework, and integration with Azure OpenAI, OpenAI, and local models.

## Kernel Setup

The `Kernel` is the central object in Semantic Kernel. It manages AI service connections, plugins, and function invocation.

### Package Landscape

| Package | Purpose |
|---------|---------|
| `Microsoft.SemanticKernel` | Core kernel, function calling, prompt templates |
| `Microsoft.SemanticKernel.Connectors.AzureOpenAI` | Azure OpenAI chat/embedding/image services |
| `Microsoft.SemanticKernel.Connectors.OpenAI` | OpenAI chat/embedding/image services |
| `Microsoft.SemanticKernel.Connectors.Ollama` | Ollama local model integration |
| `Microsoft.SemanticKernel.Plugins.Core` | Built-in plugins (time, math, text) |
| `Microsoft.SemanticKernel.Agents.Core` | Agent framework (chat agents, group chat) |
| `Microsoft.Extensions.VectorData.Abstractions` | Vector store abstraction layer |
| `Microsoft.SemanticKernel.Connectors.Qdrant` | Qdrant vector store connector |
| `Microsoft.SemanticKernel.Connectors.AzureAISearch` | Azure AI Search vector store connector |

### Basic Kernel Configuration

```csharp
using Microsoft.SemanticKernel;

var builder = Kernel.CreateBuilder();

// Azure OpenAI
builder.AddAzureOpenAIChatCompletion(
    deploymentName: "gpt-4o",
    endpoint: Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT")!,
    apiKey: Environment.GetEnvironmentVariable("AZURE_OPENAI_API_KEY")!);

var kernel = builder.Build();
```

### DI Integration with ASP.NET Core

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddKernel();

builder.Services.AddAzureOpenAIChatCompletion(
    deploymentName: builder.Configuration["AI:DeploymentName"]!,
    endpoint: builder.Configuration["AI:Endpoint"]!,
    apiKey: builder.Configuration["AI:ApiKey"]!);

// Register plugins
builder.Services.AddSingleton<OrderPlugin>();
builder.Services.AddSingleton(sp =>
{
    var kernel = sp.GetRequiredService<Kernel>();
    kernel.Plugins.AddFromObject(sp.GetRequiredService<OrderPlugin>());
    return kernel;
});
```

### Multiple AI Services

Register multiple AI services and select by service ID:

```csharp
var builder = Kernel.CreateBuilder();

builder.AddAzureOpenAIChatCompletion(
    deploymentName: "gpt-4o",
    endpoint: endpoint,
    apiKey: apiKey,
    serviceId: "gpt4o");

builder.AddAzureOpenAIChatCompletion(
    deploymentName: "gpt-4o-mini",
    endpoint: endpoint,
    apiKey: apiKey,
    serviceId: "gpt4o-mini");

var kernel = builder.Build();

// Select service at invocation time
var settings = new PromptExecutionSettings { ServiceId = "gpt4o-mini" };
var result = await kernel.InvokePromptAsync("Summarize: {{$input}}", new(settings)
{
    ["input"] = longDocument
});
```

### Local Models with Ollama

```csharp
#pragma warning disable SKEXP0070  // Ollama connector is experimental

var builder = Kernel.CreateBuilder();

builder.AddOllamaChatCompletion(
    modelId: "llama3.2",
    endpoint: new Uri("http://localhost:11434"));

var kernel = builder.Build();
```

---

## Plugins and Function Calling

Plugins expose .NET methods as functions that the AI model can invoke. This is the primary mechanism for grounding LLM responses in real data and actions.

### Defining a Plugin

```csharp
using Microsoft.SemanticKernel;
using System.ComponentModel;

public sealed class OrderPlugin
{
    private readonly IOrderRepository _repository;

    public OrderPlugin(IOrderRepository repository) => _repository = repository;

    [KernelFunction("get_order")]
    [Description("Retrieves an order by its ID")]
    public async Task<OrderSummary?> GetOrderAsync(
        [Description("The unique order identifier")] string orderId,
        CancellationToken ct = default)
    {
        var order = await _repository.GetByIdAsync(orderId, ct);
        return order is null ? null : new OrderSummary(order);
    }

    [KernelFunction("list_recent_orders")]
    [Description("Lists the most recent orders for a customer")]
    public async Task<IReadOnlyList<OrderSummary>> ListRecentOrdersAsync(
        [Description("The customer ID")] string customerId,
        [Description("Maximum number of orders to return")] int limit = 10,
        CancellationToken ct = default)
    {
        var orders = await _repository.GetRecentAsync(customerId, limit, ct);
        return orders.Select(o => new OrderSummary(o)).ToList();
    }
}
```

### Registering Plugins

```csharp
var kernel = builder.Build();

// From an object instance (DI-friendly)
kernel.Plugins.AddFromObject(new OrderPlugin(orderRepo), "Orders");

// From a type (kernel creates the instance)
kernel.Plugins.AddFromType<TimePlugin>("Time");

// From functions directly
kernel.Plugins.AddFromFunctions("Math",
[
    KernelFunctionFactory.CreateFromMethod(
        ([Description("First number")] double a, [Description("Second number")] double b) => a + b,
        "Add",
        "Adds two numbers")
]);
```

### Automatic Function Calling

Enable the model to call functions automatically during chat:

```csharp
var settings = new AzureOpenAIPromptExecutionSettings
{
    FunctionChoiceBehavior = FunctionChoiceBehavior.Auto()
};

var chatHistory = new ChatHistory();
chatHistory.AddUserMessage("What's the status of order ORD-12345?");

var result = await kernel.GetRequiredService<IChatCompletionService>()
    .GetChatMessageContentAsync(chatHistory, settings, kernel);

// The model calls get_order("ORD-12345") automatically and responds with the result
Console.WriteLine(result.Content);
```

### Function Filters

Intercept function calls for logging, authorization, or modification:

```csharp
public sealed class AuthorizationFilter : IFunctionInvocationFilter
{
    public async Task OnFunctionInvocationAsync(
        FunctionInvocationContext context,
        Func<FunctionInvocationContext, Task> next)
    {
        // Check authorization before function execution
        if (context.Function.Name == "get_order")
        {
            var orderId = context.Arguments["orderId"]?.ToString();
            // Validate access...
        }

        await next(context);

        // Post-execution: log or modify result
    }
}

// Register the filter
builder.Services.AddSingleton<IFunctionInvocationFilter, AuthorizationFilter>();
```

---

## Prompt Templates

Prompt templates support variable substitution and function calling within structured prompts.

### Inline Prompts

```csharp
var result = await kernel.InvokePromptAsync(
    "Summarize the following text in {{$style}} style:\n\n{{$input}}",
    new KernelArguments
    {
        ["input"] = articleText,
        ["style"] = "concise bullet points"
    });
```

### Handlebars Templates

Handlebars templates support conditionals, loops, and function calls:

```csharp
var templateString = """
    <message role="system">
    You are a helpful customer service agent.
    {{#if isVip}}You are speaking with a VIP customer. Be extra attentive.{{/if}}
    </message>
    <message role="user">
    Customer: {{customerName}}
    Query: {{query}}

    Recent orders:
    {{#each orders}}
    - Order {{this.Id}}: {{this.Status}} ({{this.Date}})
    {{/each}}
    </message>
    """;

var factory = new HandlebarsPromptTemplateFactory();
var template = factory.Create(new PromptTemplateConfig(templateString)
{
    TemplateFormat = HandlebarsPromptTemplateFactory.HandlebarsTemplateFormat
});

var result = await template.RenderAsync(kernel, new KernelArguments
{
    ["customerName"] = "Alice",
    ["query"] = "Where is my order?",
    ["isVip"] = true,
    ["orders"] = recentOrders
});
```

### YAML Prompt Configuration

Define prompts as YAML files for separation of concerns:

```yaml
# prompts/summarize.yaml
name: Summarize
description: Summarizes text to a specified length
template_format: handlebars
template: |
  <message role="system">
  Summarize the following text in approximately {{maxWords}} words.
  Focus on key facts and actionable items.
  </message>
  <message role="user">{{input}}</message>
input_variables:
  - name: input
    description: The text to summarize
    is_required: true
  - name: maxWords
    description: Target word count
    default: "100"
execution_settings:
  default:
    temperature: 0.3
    max_tokens: 500
```

```csharp
var yamlContent = File.ReadAllText("prompts/summarize.yaml");
var function = kernel.CreateFunctionFromPromptYaml(yamlContent);

var result = await kernel.InvokeAsync(function, new KernelArguments
{
    ["input"] = longText,
    ["maxWords"] = "50"
});
```

---

## Memory and Vector Stores

Semantic Kernel provides abstractions for vector storage, enabling retrieval-augmented generation (RAG) patterns.

### Vector Store Abstractions

```csharp
using Microsoft.Extensions.VectorData;

public sealed class DocumentRecord
{
    [VectorStoreRecordKey]
    public string Id { get; set; } = string.Empty;

    [VectorStoreRecordData(IsFilterable = true)]
    public string Source { get; set; } = string.Empty;

    [VectorStoreRecordData(IsFullTextSearchable = true)]
    public string Content { get; set; } = string.Empty;

    [VectorStoreRecordVector(Dimensions: 1536)]
    public ReadOnlyMemory<float> Embedding { get; set; }
}
```

### Registering a Vector Store

```csharp
using Microsoft.SemanticKernel.Connectors.Qdrant;

var builder = Kernel.CreateBuilder();

// Register embedding generation
builder.AddAzureOpenAITextEmbeddingGeneration(
    deploymentName: "text-embedding-3-small",
    endpoint: endpoint,
    apiKey: apiKey);

// Register vector store
builder.Services.AddQdrantVectorStore("localhost", 6334);
```

### RAG Pattern

```csharp
public sealed class RagService
{
    private readonly IVectorStoreRecordCollection<string, DocumentRecord> _collection;
    private readonly ITextEmbeddingGenerationService _embeddingService;
    private readonly IChatCompletionService _chatService;

    public RagService(
        IVectorStore vectorStore,
        ITextEmbeddingGenerationService embeddingService,
        IChatCompletionService chatService)
    {
        _collection = vectorStore.GetCollection<string, DocumentRecord>("documents");
        _embeddingService = embeddingService;
        _chatService = chatService;
    }

    public async Task<string> AskAsync(string question, CancellationToken ct = default)
    {
        // 1. Generate embedding for the question
        var questionEmbedding = await _embeddingService
            .GenerateEmbeddingAsync(question, cancellationToken: ct);

        // 2. Search for relevant documents
        var searchResults = _collection.VectorizedSearchAsync(
            questionEmbedding,
            new VectorSearchOptions { Top = 5 },
            ct);

        // 3. Build context from search results
        var contextBuilder = new StringBuilder();
        await foreach (var result in searchResults)
        {
            contextBuilder.AppendLine(result.Record.Content);
            contextBuilder.AppendLine("---");
        }

        // 4. Generate answer with context
        var chatHistory = new ChatHistory();
        chatHistory.AddSystemMessage(
            $"Answer based on the following context:\n\n{contextBuilder}");
        chatHistory.AddUserMessage(question);

        var response = await _chatService
            .GetChatMessageContentAsync(chatHistory, cancellationToken: ct);

        return response.Content ?? string.Empty;
    }
}
```

### Ingesting Documents

```csharp
public async Task IngestAsync(
    string documentId,
    string content,
    string source,
    CancellationToken ct = default)
{
    await _collection.CreateCollectionIfNotExistsAsync(ct);

    var embedding = await _embeddingService
        .GenerateEmbeddingAsync(content, cancellationToken: ct);

    await _collection.UpsertAsync(new DocumentRecord
    {
        Id = documentId,
        Content = content,
        Source = source,
        Embedding = embedding
    }, cancellationToken: ct);
}
```

---

## Agents Framework

The Semantic Kernel agents framework enables building multi-agent systems where specialized agents collaborate on tasks.

### Chat Completion Agent

```csharp
#pragma warning disable SKEXP0110  // Agents framework is experimental

using Microsoft.SemanticKernel.Agents;

var agent = new ChatCompletionAgent
{
    Name = "OrderAssistant",
    Instructions = """
        You are an order management assistant. Help customers check order status,
        process returns, and answer questions about their orders.
        Always verify the customer's identity before sharing order details.
        """,
    Kernel = kernel,
    Arguments = new KernelArguments(new AzureOpenAIPromptExecutionSettings
    {
        FunctionChoiceBehavior = FunctionChoiceBehavior.Auto()
    })
};

// Invoke via a thread (required -- agents do not accept bare strings)
var thread = new ChatHistoryAgentThread();
await foreach (var message in agent.InvokeAsync(
    "What's the status of my order ORD-12345?", thread))
{
    Console.WriteLine(message.Content);
}
```

### Agent Group Chat

Multiple agents can collaborate in a group chat with termination conditions:

```csharp
var analyst = new ChatCompletionAgent
{
    Name = "DataAnalyst",
    Instructions = "You analyze data and provide insights. Present findings clearly.",
    Kernel = kernel
};

var writer = new ChatCompletionAgent
{
    Name = "ReportWriter",
    Instructions = "You take analytical findings and write clear, actionable reports.",
    Kernel = kernel
};

var chat = new AgentGroupChat(analyst, writer)
{
    ExecutionSettings = new AgentGroupChatSettings
    {
        TerminationStrategy = new ApprovalTerminationStrategy
        {
            MaximumIterations = 6
        }
    }
};

chat.AddChatMessage(
    new ChatMessageContent(AuthorRole.User, "Analyze Q4 sales trends and write a summary report."));

await foreach (var message in chat.InvokeAsync())
{
    Console.WriteLine($"[{message.AuthorName}]: {message.Content}");
}
```

### OpenAI Assistant Agent

For stateful conversations with built-in tools (code interpreter, file search):

```csharp
#pragma warning disable SKEXP0110

// Create the assistant via the builder pattern
OpenAIAssistantAgent agent = await OpenAIAssistantAgent.CreateAsync(
    kernel,
    new OpenAIAssistantDefinition("gpt-4o")
    {
        Name = "DataProcessor",
        Instructions = "You process CSV data and generate insights.",
        EnableCodeInterpreter = true
    });

try
{
    // Assistant agents use threads for stateful conversations
    var thread = await agent.CreateThreadAsync();

    await foreach (var message in agent.InvokeAsync(
        "Analyze the attached sales data.", thread))
    {
        Console.WriteLine(message.Content);
    }
}
finally
{
    await agent.DeleteAsync();
}
```

Note: The agents framework is experimental (`SKEXP0110`). APIs change frequently between Semantic Kernel releases. Verify method signatures against the [latest samples](https://github.com/microsoft/semantic-kernel/tree/main/dotnet/samples) when adopting.

---

## Streaming Responses

For chat applications, stream responses token-by-token:

```csharp
var chatService = kernel.GetRequiredService<IChatCompletionService>();
var chatHistory = new ChatHistory("You are a helpful assistant.");
chatHistory.AddUserMessage(userInput);

var settings = new AzureOpenAIPromptExecutionSettings
{
    FunctionChoiceBehavior = FunctionChoiceBehavior.Auto()
};

await foreach (var chunk in chatService.GetStreamingChatMessageContentsAsync(
    chatHistory, settings, kernel))
{
    Console.Write(chunk.Content);
}
```

---

## Key Principles

- **Use function calling over prompt stuffing** -- let the model call plugins to retrieve real-time data rather than injecting everything into the prompt
- **Keep plugins focused** -- each plugin should represent a single domain; use `[Description]` attributes on functions and parameters so the model knows when and how to call them
- **Use YAML prompts for production** -- separate prompt content from code for easier iteration and non-developer editing
- **Do not store API keys in code** -- use environment variables, Azure Key Vault, or the .NET secrets manager (see [skill:dotnet-csharp])
- **Prefer vector store abstractions** -- code against `IVectorStore` to allow switching between Qdrant, Azure AI Search, and other providers
- **Handle experimental APIs explicitly** -- suppress `SKEXP*` warnings per-call, not globally, so you notice when APIs graduate to stable

---

## Agent Gotchas

1. **Do not hardcode API keys or endpoints in Kernel builder calls** -- use `builder.Configuration` or environment variables. Hardcoded secrets leak into source control and prevent environment-specific configuration.
2. **Do not suppress all `SKEXP*` warnings globally** -- experimental APIs change frequently. Suppress per-usage (`#pragma warning disable SKEXP0110`) so new experimental usage sites are flagged by the compiler.
3. **Do not create a new `Kernel` instance per request in ASP.NET Core** -- register the kernel in DI as a singleton (it is thread-safe) and clone with `kernel.Clone()` if per-request state is needed.
4. **Do not ignore `CancellationToken` in plugin functions** -- AI function calls can be cancelled by the user or timeout policies. Always propagate `CancellationToken` through plugin method signatures.
5. **Do not return large objects from plugin functions** -- the model receives the serialized result as context. Return summary DTOs, not full entity graphs, to avoid exceeding token limits.
6. **Do not mix `AddAzureOpenAIChatCompletion` and `AddOpenAIChatCompletion` without `serviceId`** -- without a service ID, the last registration wins. Use explicit `serviceId` when registering multiple AI services.

---

## Prerequisites

- `Microsoft.SemanticKernel` NuGet package (1.x stable)
- An AI service endpoint (Azure OpenAI, OpenAI API key, or Ollama for local models)
- For vector stores: a running instance of the chosen provider (Qdrant, Azure AI Search, etc.)

---

## References

- [Semantic Kernel documentation](https://learn.microsoft.com/en-us/semantic-kernel/)
- [Semantic Kernel .NET SDK](https://github.com/microsoft/semantic-kernel)
- [Semantic Kernel plugins](https://learn.microsoft.com/en-us/semantic-kernel/concepts/plugins/)
- [Semantic Kernel agents](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/)
- [Vector store connectors](https://learn.microsoft.com/en-us/semantic-kernel/concepts/vector-store-connectors/)
- [Semantic Kernel samples](https://github.com/microsoft/semantic-kernel/tree/main/dotnet/samples)
