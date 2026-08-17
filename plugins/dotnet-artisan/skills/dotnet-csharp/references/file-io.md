# File I/O

File I/O patterns for .NET applications. Covers FileStream construction with async flags, RandomAccess API for thread-safe offset-based I/O, File convenience methods, FileSystemWatcher event handling and debouncing, MemoryMappedFile for large files and IPC, path handling security (Combine vs Join), secure temp file creation, cross-platform considerations, IOException hierarchy, and buffer sizing guidance.

## FileStream

### Async Flag Requirement

FileStream async methods (`ReadAsync`, `WriteAsync`) silently block the calling thread unless the stream is opened with the async flag. This is the most common file I/O mistake in .NET code.

```csharp
// CORRECT: async-capable FileStream
await using var fs = new FileStream(
    path,
    FileMode.Open,
    FileAccess.Read,
    FileShare.Read,
    bufferSize: 4096,
    useAsync: true);  // Required for true async I/O

byte[] buffer = new byte[4096];
int bytesRead = await fs.ReadAsync(buffer, cancellationToken);
```

```csharp
// ALSO CORRECT: FileOptions overload
await using var fs = new FileStream(
    path,
    FileMode.Create,
    FileAccess.Write,
    FileShare.None,
    bufferSize: 4096,
    FileOptions.Asynchronous | FileOptions.SequentialScan);
```

Without `useAsync: true` or `FileOptions.Asynchronous`, the runtime emulates async by dispatching synchronous I/O to the thread pool -- wasting a thread and adding overhead.

### FileStreamOptions (.NET 6+)

```csharp
await using var fs = new FileStream(path, new FileStreamOptions
{
    Mode = FileMode.Open,
    Access = FileAccess.Read,
    Share = FileShare.Read,
    Options = FileOptions.Asynchronous | FileOptions.SequentialScan,
    BufferSize = 4096,
    PreallocationSize = 1_048_576  // Hint for write: reduces fragmentation
});
```

`PreallocationSize` reserves disk space upfront when creating or overwriting files, reducing filesystem fragmentation on writes.

---

## RandomAccess API (.NET 6+)

`RandomAccess` provides static, offset-based, thread-safe file I/O. Unlike FileStream, it has no internal position state, so multiple threads can read/write different offsets concurrently without synchronization.

```csharp
using var handle = File.OpenHandle(
    path,
    FileMode.Open,
    FileAccess.Read,
    FileShare.Read,
    FileOptions.Asynchronous);

// Thread-safe: offset is explicit, no shared position
byte[] buffer = new byte[4096];
int bytesRead = await RandomAccess.ReadAsync(
    handle, buffer, fileOffset: 0, cancellationToken);

// Read from a different offset concurrently -- no locking needed
byte[] buffer2 = new byte[4096];
int bytesRead2 = await RandomAccess.ReadAsync(
    handle, buffer2, fileOffset: 8192, cancellationToken);
```

### Scatter/Gather I/O

```csharp
// Read into multiple buffers in a single syscall
IReadOnlyList<Memory<byte>> buffers = new[]
{
    new byte[4096].AsMemory(),
    new byte[4096].AsMemory()
};
long totalRead = await RandomAccess.ReadAsync(
    handle, buffers, fileOffset: 0, cancellationToken);
```

### When to Use RandomAccess vs FileStream

| Scenario | Use |
|----------|-----|
| Concurrent reads from different offsets | RandomAccess |
| Sequential streaming reads/writes | FileStream |
| Index files, database pages, memory-mapped alternatives | RandomAccess |
| Integration with Stream-based APIs | FileStream |

---

## File Convenience Methods

For small files where streaming is unnecessary, the `File` static methods are simpler and correct.

```csharp
// Read entire file as string (small files only)
string content = await File.ReadAllTextAsync(path, cancellationToken);

// Read all lines
string[] lines = await File.ReadAllLinesAsync(path, cancellationToken);

// Stream lines without loading entire file (.NET 8+)
await foreach (string line in File.ReadLinesAsync(path, cancellationToken))
{
    ProcessLine(line);
}

// Write text atomically (write-then-rename pattern not built-in)
await File.WriteAllTextAsync(path, content, cancellationToken);

// Read all bytes
byte[] data = await File.ReadAllBytesAsync(path, cancellationToken);
```

### When Convenience Methods Are Appropriate

| File size | Approach |
|-----------|----------|
| < 1 MB | `File.ReadAllTextAsync` / `File.ReadAllBytesAsync` |
| 1--100 MB | `File.ReadLinesAsync` or FileStream with buffered reading |
| > 100 MB | FileStream or RandomAccess with explicit buffer management |

---

## FileSystemWatcher

### Basic Setup

```csharp
using var watcher = new FileSystemWatcher(directoryPath)
{
    Filter = "*.json",
    NotifyFilter = NotifyFilters.FileName
                 | NotifyFilters.LastWrite
                 | NotifyFilters.Size,
    IncludeSubdirectories = true,
    EnableRaisingEvents = true
};

watcher.Changed += OnChanged;
watcher.Created += OnCreated;
watcher.Deleted += OnDeleted;
watcher.Renamed += OnRenamed;
watcher.Error += OnError;
```

### Debouncing Duplicate Events

FileSystemWatcher fires duplicate events for a single logical change (editors write temp file, rename, delete old). Debounce with a timer.

```csharp
public sealed class DebouncedFileWatcher : IDisposable
{
    private readonly FileSystemWatcher _watcher;
    private readonly Channel<string> _channel;
    private readonly CancellationTokenSource _cts = new();

    public DebouncedFileWatcher(string path, string filter)
    {
        _channel = Channel.CreateBounded<string>(
            new BoundedChannelOptions(100)
            {
                FullMode = BoundedChannelFullMode.DropOldest
            });

        _watcher = new FileSystemWatcher(path, filter)
        {
            EnableRaisingEvents = true
        };
        _watcher.Changed += (_, e) =>
            _channel.Writer.TryWrite(e.FullPath);
    }

    // requires: using System.Runtime.CompilerServices;
    public async IAsyncEnumerable<string> WatchAsync(
        TimeSpan debounce,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        using var linked = CancellationTokenSource
            .CreateLinkedTokenSource(ct, _cts.Token);
        var seen = new Dictionary<string, DateTime>();

        await foreach (var path in
            _channel.Reader.ReadAllAsync(linked.Token))
        {
            var now = DateTime.UtcNow;
            if (seen.TryGetValue(path, out var last)
                && now - last < debounce)
                continue;

            seen[path] = now;
            yield return path;
        }
    }

    public void Dispose()
    {
        _cts.Cancel();
        _watcher.Dispose();
        _cts.Dispose();
    }
}
```

### Buffer Overflow

The internal buffer defaults to 8 KB. When many changes occur rapidly, the buffer overflows and events are lost. Increase with `InternalBufferSize` (max 64 KB on Windows) and handle the `Error` event.

```csharp
watcher.InternalBufferSize = 65_536;  // 64 KB
watcher.Error += (_, e) =>
{
    if (e.GetException() is InternalBufferOverflowException)
    {
        logger.LogWarning("FileSystemWatcher buffer overflow -- events lost");
        // Trigger full directory rescan
    }
};
```

### Platform Differences

| Platform | Backend | Notable behavior |
|----------|---------|-----------------|
| Windows | ReadDirectoryChangesW | Most reliable; supports `InternalBufferSize` up to 64 KB |
| Linux | inotify | Watch limit per user (`/proc/sys/fs/inotify/max_user_watches`); recursive watches add one inotify watch per subdirectory |
| macOS | FSEvents (kqueue fallback) | Coarser event granularity; may batch events with slight delay |

---

## MemoryMappedFile

### Persisted (Large File Access)

Map a file into virtual memory for random access without explicit read/write calls. Efficient for large files that do not fit in memory -- the OS pages data in and out as needed.

```csharp
using var mmf = MemoryMappedFile.CreateFromFile(
    path,
    FileMode.Open,
    mapName: null,
    capacity: 0,  // Use file's actual size
    MemoryMappedFileAccess.Read);

using var accessor = mmf.CreateViewAccessor(
    offset: 0,
    size: 0,  // Map entire file
    MemoryMappedFileAccess.Read);

// Read a struct at a specific offset
accessor.Read<MyHeader>(position: 0, out var header);

// Or use a view stream for sequential access
using var stream = mmf.CreateViewStream(
    offset: 0,
    size: 4096,
    MemoryMappedFileAccess.Read);
```

### Non-Persisted (IPC Shared Memory)

```csharp
// Process A: create shared memory region
using var mmf = MemoryMappedFile.CreateNew(
    "SharedRegion",
    capacity: 1_048_576,  // 1 MB
    MemoryMappedFileAccess.ReadWrite);

using var accessor = mmf.CreateViewAccessor();
accessor.Write(0, 42);

// Process B: open existing shared memory region
using var mmf2 = MemoryMappedFile.OpenExisting(
    "SharedRegion",
    MemoryMappedFileRights.Read);

using var accessor2 = mmf2.CreateViewAccessor(
    0, 0, MemoryMappedFileAccess.Read);
int value = accessor2.ReadInt32(0);  // 42
```

For GC implications of memory-mapped backing arrays and POH usage, see [skill:dotnet-tooling].

---

## Path Handling

### Path.Combine vs Path.Join Security

`Path.Combine` silently discards the first argument when the second argument is a rooted path. This enables path traversal attacks when user input is passed as the second argument.

```csharp
// DANGEROUS: Path.Combine drops basePath when userInput is rooted
string basePath = "/app/uploads";
string userInput = "/etc/passwd";
string result = Path.Combine(basePath, userInput);
// result = "/etc/passwd"  -- basePath is silently ignored

// SAFER: Path.Join does not discard on rooted paths (.NET Core 2.1+)
string result2 = Path.Join(basePath, userInput);
// result2 = "/app/uploads//etc/passwd"  -- preserves basePath
```

### Path Traversal Prevention

```csharp
public static string SafeResolvePath(string basePath, string userPath)
{
    // Resolve to absolute, resolving ../ and symlinks
    string fullBase = Path.GetFullPath(basePath);
    string fullPath = Path.GetFullPath(
        Path.Join(fullBase, userPath));

    // OrdinalIgnoreCase: safe cross-platform default.
    // On Linux-only deployments, Ordinal is more precise.
    if (!fullPath.StartsWith(fullBase + Path.DirectorySeparatorChar,
            StringComparison.OrdinalIgnoreCase)
        && !fullPath.Equals(fullBase, StringComparison.OrdinalIgnoreCase))
    {
        throw new UnauthorizedAccessException(
            "Path traversal detected");
    }

    return fullPath;
}
```

### Cross-Platform Path Separators

Use `Path.DirectorySeparatorChar` (platform-specific) and `Path.AltDirectorySeparatorChar` instead of hardcoded `/` or `\\`. `Path.Join` and `Path.Combine` handle separator normalization automatically.

---

## Secure Temp Files

`Path.GetTempFileName()` creates a zero-byte file with a predictable name pattern and throws when the temp directory contains 65,535 `.tmp` files. Use `Path.GetRandomFileName()` instead.

```csharp
// INSECURE: predictable name, may throw IOException
// string tempFile = Path.GetTempFileName();

// SECURE: cryptographically random name, explicit creation
string tempPath = Path.Join(
    Path.GetTempPath(),
    Path.GetRandomFileName());

// CreateNew ensures atomic creation -- fails if file exists
await using var fs = new FileStream(
    tempPath,
    FileMode.CreateNew,
    FileAccess.Write,
    FileShare.None,
    bufferSize: 4096,
    FileOptions.Asynchronous | FileOptions.DeleteOnClose);

await fs.WriteAsync(data, cancellationToken);
```

`FileOptions.DeleteOnClose` ensures the temp file is removed when the stream is closed. On Windows, the OS guarantees deletion when the last handle closes. On Linux/macOS, deletion happens during `Dispose` and may not occur if the process is killed abruptly (SIGKILL).

---

## Cross-Platform Considerations

### Case Sensitivity

| Platform | Default filesystem | Case behavior |
|----------|-------------------|---------------|
| Windows | NTFS | Case-preserving, case-insensitive |
| macOS | APFS | Case-preserving, case-insensitive (default) |
| Linux | ext4/xfs | Case-sensitive |

Use `StringComparison.OrdinalIgnoreCase` for path comparisons that must work cross-platform. Do not assume case sensitivity behavior -- check at runtime if needed.

### UnixFileMode (.NET 7+)

```csharp
// Set POSIX permissions on file creation (Linux/macOS only)
await using var fs = new FileStream(path, new FileStreamOptions
{
    Mode = FileMode.Create,
    Access = FileAccess.Write,
    UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite
    // 0600 -- owner read/write only
});
```

On Windows, `UnixCreateMode` is silently ignored. Do not use it as a security control on Windows -- use ACLs or Windows security APIs instead.

### File Locking

| Platform | Lock type | Behavior |
|----------|-----------|----------|
| Windows | Mandatory | Other processes cannot read/write locked regions |
| Linux | Advisory (flock/fcntl) | Locks are cooperative -- processes can ignore them |
| macOS | Advisory (flock) | Same as Linux -- cooperative |

`FileShare` flags control sharing on Windows. On Linux/macOS, use `FileStream.Lock` for advisory locking but be aware that non-cooperating processes can bypass it.

---

## Error Handling

### IOException Hierarchy

```
IOException
  +-- FileNotFoundException
  +-- DirectoryNotFoundException
  +-- PathTooLongException
  +-- DriveNotFoundException
  +-- EndOfStreamException
  +-- FileLoadException
```

### HResult Codes for Specific Conditions

```csharp
try
{
    await using var fs = new FileStream(path,
        FileMode.Open, FileAccess.Read);
    // ...
}
catch (IOException ex) when (ex.HResult == unchecked((int)0x80070070))
{
    // ERROR_DISK_FULL (Windows) -- disk full
    logger.LogError("Disk full: {Path}", path);
}
catch (IOException ex) when (ex.HResult == unchecked((int)0x80070020))
{
    // ERROR_SHARING_VIOLATION -- file locked by another process
    logger.LogWarning("File locked: {Path}", path);
}
catch (UnauthorizedAccessException ex)
{
    // Permission denied (not an IOException subclass)
    logger.LogError("Access denied: {Path}", path);
}
```

### Disk-Full Flush Behavior

Write operations may succeed but buffer data in memory. A disk-full condition can surface at `Flush` or `Dispose` time rather than at the `Write` call. Always check for exceptions on flush.

```csharp
await using var fs = new FileStream(path,
    FileMode.Create, FileAccess.Write,
    FileShare.None, 4096, FileOptions.Asynchronous);

await fs.WriteAsync(data, cancellationToken);

// IOException (disk full) may throw here, not at WriteAsync
await fs.FlushAsync(cancellationToken);
```

---

## Buffer Sizing

Guidance based on dotnet/runtime benchmarks and internal FileStream implementation:

| File operation | Recommended buffer | Rationale |
|---------------|-------------------|-----------|
| Small file sequential read (< 1 MB) | 4 KB (default) | Matches OS page size; FileStream default |
| Large file sequential read (> 1 MB) | 64--128 KB | Amortizes syscall overhead; diminishing returns above 128 KB |
| Network-attached storage (NFS/SMB) | 64 KB | Larger buffers amortize network round-trips |
| SSD random access | 4 KB | Matches SSD page size; larger buffers waste read-ahead |
| FileStream sequential scan | 4 KB + `FileOptions.SequentialScan` | OS read-ahead handles prefetching |

`FileOptions.SequentialScan` hints the OS to prefetch data ahead of the read position. It is beneficial for sequential reads and can degrade performance for random access patterns.

---

## Agent Gotchas

1. **Do not use FileStream async methods without `useAsync: true`** -- without the async flag, `ReadAsync`/`WriteAsync` dispatch synchronous I/O to the thread pool, blocking a thread and adding overhead. Always pass `useAsync: true` or `FileOptions.Asynchronous`.
2. **Do not use `Path.Combine` with untrusted input** -- `Path.Combine` silently discards the base path when the second argument is rooted, enabling path traversal. Use `Path.Join` (.NET Core 2.1+) and validate the resolved path is under the intended base directory.
3. **Do not use `Path.GetTempFileName()`** -- it creates predictable filenames and throws at 65,535 files. Use `Path.GetRandomFileName()` with `FileMode.CreateNew` for secure, atomic temp file creation.
4. **Do not ignore FileSystemWatcher duplicate events** -- editors and tools trigger multiple events for a single logical change. Implement debouncing with a timer or Channel<T> throttle.
5. **Do not rely on FileSystemWatcher alone for reliable change detection** -- buffer overflows lose events silently. Handle the `Error` event and implement periodic rescan as a fallback.
6. **Do not assume file locking is mandatory on Linux/macOS** -- `FileStream.Lock` and `FileShare` flags use advisory locking on Unix, which non-cooperating processes can bypass. Design protocols accordingly.
7. **Do not catch only `IOException` and ignore `UnauthorizedAccessException`** -- permission errors throw `UnauthorizedAccessException`, which does not inherit from `IOException`. Handle both in file access error handling.
8. **Do not assume `WriteAsync` reports disk-full errors immediately** -- data may be buffered. Disk-full `IOException` can surface at `FlushAsync` or `Dispose`. Always handle exceptions on flush.

---

## References

- [File and stream I/O overview](https://learn.microsoft.com/en-us/dotnet/standard/io/)
- [.NET 6 file I/O improvements](https://devblogs.microsoft.com/dotnet/file-io-improvements-in-dotnet-6/)
- [RandomAccess API](https://learn.microsoft.com/en-us/dotnet/api/system.io.randomaccess)
- [FileSystemWatcher](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher)
- [Memory-mapped files](https://learn.microsoft.com/en-us/dotnet/standard/io/memory-mapped-files)
- [Path traversal prevention (OWASP)](https://owasp.org/www-community/attacks/Path_Traversal)
- [Secure temp files](https://docs.datadoghq.com/security/code_security/static_analysis/static_analysis_rules/csharp-security/unsafe-temp-file/)
