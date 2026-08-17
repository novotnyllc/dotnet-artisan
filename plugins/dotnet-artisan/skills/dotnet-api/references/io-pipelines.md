# I/O Pipelines

High-performance I/O patterns using `System.IO.Pipelines`. Covers `PipeReader`, `PipeWriter`, backpressure management, protocol parser implementation, and Kestrel integration. Pipelines solve the classic problems of buffer management, incomplete reads, and memory copying that plague traditional stream-based network code.

## Why Pipelines Over Streams

Traditional `Stream`-based I/O forces developers to manage buffers manually, handle partial reads, and copy data between buffers. `System.IO.Pipelines` solves these problems:

| Problem | Stream Approach | Pipeline Approach |
|---------|----------------|-------------------|
| Buffer management | Allocate `byte[]`, resize manually | Automatic pooled buffer management |
| Partial reads | Track position, concatenate fragments | `ReadResult` with `SequencePosition` bookmarks |
| Backpressure | None -- writer can outpace reader | Built-in pause/resume thresholds |
| Memory copies | Copy between buffers at each layer | Zero-copy slicing with `ReadOnlySequence<byte>` |
| Lifetime management | Manual `byte[]` lifecycle | Pooled memory returned on `AdvanceTo` |

The `Pipe` class connects a `PipeWriter` (producer) and a `PipeReader` (consumer) with an internal buffer pool, flow control, and completion signaling.

---

## Core Concepts

### Pipe, PipeReader, PipeWriter

```csharp
// Create a pipe with default options (uses ArrayPool internally)
var pipe = new Pipe();

PipeWriter writer = pipe.Writer;  // Producer side
PipeReader reader = pipe.Reader;  // Consumer side
```

### PipeWriter -- Producing Data

```csharp
async Task FillPipeAsync(Stream source, PipeWriter writer,
    CancellationToken ct)
{
    const int minimumBufferSize = 512;

    while (true)
    {
        // Request a buffer from the pipe's memory pool
        Memory<byte> memory = writer.GetMemory(minimumBufferSize);

        int bytesRead = await source.ReadAsync(memory, ct);
        if (bytesRead == 0)
            break;  // End of stream

        // Tell the pipe how many bytes were written
        writer.Advance(bytesRead);

        // Flush makes data available to the reader.
        // FlushAsync may pause here if the reader is slow (backpressure).
        FlushResult result = await writer.FlushAsync(ct);
        if (result.IsCompleted)
            break;  // Reader stopped consuming
    }

    // Signal completion -- reader will see IsCompleted = true
    await writer.CompleteAsync();
}
```

**Critical rules:**
- Call `GetMemory` or `GetSpan` before writing -- never write to a previously obtained buffer after `Advance`
- Call `Advance` with the exact number of bytes written
- Call `FlushAsync` to make data available to the reader and to respect backpressure

### PipeReader -- Consuming Data

```csharp
async Task ReadPipeAsync(PipeReader reader, CancellationToken ct)
{
    while (true)
    {
        ReadResult result = await reader.ReadAsync(ct);
        ReadOnlySequence<byte> buffer = result.Buffer;

        // Try to parse messages from the buffer
        while (TryParseMessage(ref buffer, out var message))
        {
            await ProcessMessageAsync(message, ct);
        }

        // Tell the pipe how much was consumed and how much was examined.
        // consumed: data that has been fully processed (will be freed)
        // examined: data that has been looked at (won't trigger re-read
        //           until new data arrives)
        reader.AdvanceTo(buffer.Start, buffer.End);

        if (result.IsCompleted)
            break;  // Writer finished and all data consumed
    }

    await reader.CompleteAsync();
}
```

**Critical rules:**
- Always call `AdvanceTo` after `ReadAsync` -- failing to do so leaks memory
- Pass both `consumed` and `examined` positions: `consumed` frees memory, `examined` prevents busy-wait when the buffer has been scanned but does not contain a complete message
- Never access `ReadResult.Buffer` after calling `AdvanceTo` -- the memory may be recycled

---

## Backpressure

Backpressure prevents fast producers from overwhelming slow consumers. The pipe pauses the writer when unread data exceeds a threshold.

### PipeOptions Configuration

```csharp
var pipe = new Pipe(new PipeOptions(
    pauseWriterThreshold: 64 * 1024,   // Pause writer at 64 KB buffered
    resumeWriterThreshold: 32 * 1024,  // Resume writer when buffer drops to 32 KB
    minimumSegmentSize: 4096,
    useSynchronizationContext: false));
```

| Option | Default | Purpose |
|--------|---------|---------|
| `PauseWriterThreshold` | 65,536 | `FlushAsync` pauses when unread bytes exceed this |
| `ResumeWriterThreshold` | 32,768 | `FlushAsync` resumes when unread bytes drop below this |
| `MinimumSegmentSize` | 4,096 | Minimum buffer segment allocation size |
| `UseSynchronizationContext` | `false` | Set `false` for server code to avoid context captures |

### How Backpressure Works

1. Writer calls `FlushAsync` after `Advance`
2. If buffered (unread) data exceeds `PauseWriterThreshold`, `FlushAsync` does not complete until the reader consumes enough data to drop below `ResumeWriterThreshold`
3. The writer is effectively paused -- no busy-waiting, no exceptions, just an awaitable that completes when the reader catches up

This prevents unbounded memory growth when a producer (network socket, file) is faster than the consumer (parser, business logic).

---

## Protocol Parsing

Pipelines excel at parsing binary protocols because `ReadOnlySequence<byte>` handles fragmented data across multiple buffer segments without copying.

### Length-Prefixed Protocol Parser

A common pattern: each message starts with a 4-byte big-endian length header followed by the payload.

```csharp
static bool TryParseMessage(
    ref ReadOnlySequence<byte> buffer,
    out ReadOnlySequence<byte> payload)
{
    payload = default;

    // Need at least 4 bytes for the length prefix
    if (buffer.Length < 4)
        return false;

    // Read length from first 4 bytes
    int length;
    if (buffer.FirstSpan.Length >= 4)
    {
        length = BinaryPrimitives.ReadInt32BigEndian(buffer.FirstSpan);
    }
    else
    {
        // Slow path: length header spans multiple segments
        Span<byte> lengthBytes = stackalloc byte[4];
        buffer.Slice(0, 4).CopyTo(lengthBytes);
        length = BinaryPrimitives.ReadInt32BigEndian(lengthBytes);
    }

    // Validate length to prevent allocation attacks
    if (length < 0 || length > 1_048_576)  // 1 MB max
        throw new ProtocolViolationException(
            $"Invalid message length: {length}");

    // Check if the full message is available
    long totalLength = 4 + length;
    if (buffer.Length < totalLength)
        return false;

    // Extract the payload (zero-copy slice)
    payload = buffer.Slice(4, length);

    // Advance the buffer past this message
    buffer = buffer.Slice(totalLength);
    return true;
}
```

### Delimiter-Based Protocol Parser (Line Protocol)

```csharp
static bool TryReadLine(
    ref ReadOnlySequence<byte> buffer,
    out ReadOnlySequence<byte> line)
{
    // Look for the newline delimiter
    SequencePosition? position = buffer.PositionOf((byte)'\n');
    if (position is null)
    {
        line = default;
        return false;
    }

    // Slice up to (not including) the delimiter
    line = buffer.Slice(0, position.Value);

    // Advance past the delimiter
    buffer = buffer.Slice(buffer.GetPosition(1, position.Value));
    return true;
}
```

### Working with ReadOnlySequence<byte>

`ReadOnlySequence<byte>` may span multiple non-contiguous memory segments. Handle both paths:

```csharp
static string DecodeUtf8(ReadOnlySequence<byte> sequence)
{
    // Fast path: single contiguous segment
    if (sequence.IsSingleSegment)
    {
        return Encoding.UTF8.GetString(sequence.FirstSpan);
    }

    // Slow path: multi-segment -- rent a contiguous buffer
    int length = (int)sequence.Length;
    byte[] rented = ArrayPool<byte>.Shared.Rent(length);
    try
    {
        sequence.CopyTo(rented);
        return Encoding.UTF8.GetString(rented, 0, length);
    }
    finally
    {
        ArrayPool<byte>.Shared.Return(rented);
    }
}
```

---

## Stream Adapter

Bridge `System.IO.Pipelines` with existing `Stream`-based APIs using `PipeReader.Create` and `PipeWriter.Create`.

```csharp
// Wrap a NetworkStream for pipeline-based reading
await using var networkStream = tcpClient.GetStream();
var reader = PipeReader.Create(networkStream, new StreamPipeReaderOptions(
    bufferSize: 4096,
    minimumReadSize: 1024,
    leaveOpen: true)); // Caller manages networkStream lifetime

try
{
    await ProcessProtocolAsync(reader, cancellationToken);
}
finally
{
    await reader.CompleteAsync();
}
```

```csharp
// Wrap a stream for pipeline-based writing
var writer = PipeWriter.Create(networkStream, new StreamPipeWriterOptions(
    minimumBufferSize: 4096,
    leaveOpen: true)); // Caller manages networkStream lifetime

try
{
    await WriteResponseAsync(writer, response, cancellationToken);
}
finally
{
    await writer.CompleteAsync();
}
```

---

## Kestrel Integration

ASP.NET Core's Kestrel web server uses `System.IO.Pipelines` internally for HTTP request/response processing. Custom connection middleware can access the transport-level pipe directly.

### Connection Middleware

```csharp
// Custom connection middleware for protocol-level processing
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenLocalhost(9000, listenOptions =>
    {
        listenOptions.UseConnectionHandler<MyProtocolHandler>();
    });
});

public sealed class MyProtocolHandler : ConnectionHandler
{
    public override async Task OnConnectedAsync(
        ConnectionContext connection)
    {
        var reader = connection.Transport.Input;
        var writer = connection.Transport.Output;
        var ct = connection.ConnectionClosed;

        try
        {
            while (true)
            {
                ReadResult result = await reader.ReadAsync(ct);
                ReadOnlySequence<byte> buffer = result.Buffer;

                while (TryParseMessage(ref buffer, out var payload))
                {
                    var response = ProcessRequest(payload);
                    await WriteResponseAsync(writer, response);
                }

                reader.AdvanceTo(buffer.Start, buffer.End);

                if (result.IsCompleted)
                    break;
            }
        }
        finally
        {
            await reader.CompleteAsync();
            await writer.CompleteAsync();
        }
    }

    private static async Task WriteResponseAsync(
        PipeWriter writer, ReadOnlyMemory<byte> response)
    {
        // Write length prefix + payload
        var memory = writer.GetMemory(4 + response.Length);
        BinaryPrimitives.WriteInt32BigEndian(
            memory.Span, response.Length);
        response.CopyTo(memory[4..]);
        writer.Advance(4 + response.Length);
        await writer.FlushAsync();
    }
}
```

### IDuplexPipe

Kestrel exposes connections as `IDuplexPipe`, combining `PipeReader` and `PipeWriter` into a single transport abstraction. This pattern also works for custom TCP servers, WebSocket handlers, and named-pipe protocols.

```csharp
public interface IDuplexPipe
{
    PipeReader Input { get; }
    PipeWriter Output { get; }
}
```

---

## Performance Tips

1. **Minimize copies** -- use `ReadOnlySequence<byte>` slicing instead of copying to `byte[]`. Parse directly from the sequence when possible.
2. **Use `GetSpan`/`GetMemory` correctly** -- request the minimum size you need. The pipe may return a larger buffer, which is fine. Do not cache the returned `Span`/`Memory` across `Advance`/`FlushAsync` calls.
3. **Set `useSynchronizationContext: false`** -- server code should never capture the synchronization context. This is the default for `PipeOptions` but explicit is clearer.
4. **Tune pause/resume thresholds** -- the defaults (64 KB / 32 KB) work for most scenarios. Increase for high-throughput bulk transfer; decrease for low-latency interactive protocols.
5. **Prefer `SequenceReader<byte>`** -- for complex parsing, `SequenceReader<byte>` provides `TryRead`, `TryReadBigEndian`, `AdvancePast`, and `IsNext` methods that handle multi-segment sequences transparently.

```csharp
static bool TryParseHeader(
    ref ReadOnlySequence<byte> buffer,
    out int messageType,
    out int length)
{
    var reader = new SequenceReader<byte>(buffer);

    if (!reader.TryRead(out byte typeByte) ||
        !reader.TryReadBigEndian(out int len))
    {
        messageType = 0;
        length = 0;
        return false;
    }

    messageType = typeByte;
    length = len;
    buffer = buffer.Slice(reader.Position);
    return true;
}
```

---

## Agent Gotchas

1. **Do not forget to call `AdvanceTo` after `ReadAsync`** -- skipping `AdvanceTo` leaks pooled memory and eventually causes `OutOfMemoryException`. Every `ReadAsync` must be paired with an `AdvanceTo`.
2. **Do not access `ReadResult.Buffer` after calling `AdvanceTo`** -- the underlying memory segments may be returned to the pool. Copy or parse all needed data before advancing.
3. **Do not set `consumed` equal to `examined` when no complete message was found** -- this creates a busy-wait loop. Set `consumed` to `buffer.Start` (nothing consumed) and `examined` to `buffer.End` (everything examined) so the pipe waits for new data.
4. **Do not ignore `FlushResult.IsCompleted`** -- it means the reader has stopped consuming. Continue writing after this and data will be silently discarded.
5. **Do not use `Pipe` for simple stream-to-stream copying** -- `Stream.CopyToAsync` is simpler and equally efficient. Use pipelines when you need parsing, backpressure, or zero-copy slicing.
6. **Do not use `BinaryPrimitives` methods on spans shorter than required** -- always check `buffer.Length` before reading fixed-width values to avoid `ArgumentOutOfRangeException`.

---

## Knowledge Sources

- Stephen Toub, [System.IO.Pipelines: High performance IO in .NET](https://devblogs.microsoft.com/dotnet/system-io-pipelines-high-performance-io-in-net/) -- canonical deep dive on pipeline design, motivation, and usage patterns

## References

- [System.IO.Pipelines overview](https://learn.microsoft.com/en-us/dotnet/standard/io/pipelines)
- [Pipe class API reference](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipelines.pipe)
- [PipeReader API reference](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipelines.pipereader)
- [PipeWriter API reference](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipelines.pipewriter)
- [SequenceReader<T>](https://learn.microsoft.com/en-us/dotnet/api/system.buffers.sequencereader-1)
- [Kestrel connection middleware](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints)
