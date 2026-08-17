# Cryptography

Modern .NET cryptography covering hashing (SHA-256/384/512), symmetric encryption (AES-GCM), asymmetric cryptography (RSA, ECDSA), key derivation (PBKDF2, Argon2), and post-quantum algorithms (ML-KEM, ML-DSA, SLH-DSA) for .NET 10+. Includes TFM-aware guidance: what's available on net10.0 vs fallback strategies for net8.0/net9.0.

## Prerequisites

- .NET 8.0+ (LTS baseline for classical algorithms)
- .NET 10.0+ for post-quantum algorithms (ML-KEM, ML-DSA, SLH-DSA)
- Platform support for PQC: Windows 11 (November 2025+) or OpenSSL 3.5+ on Linux/macOS

---

## Hashing (SHA-2 Family)

Use SHA-256/384/512 for integrity verification, checksums, and content-addressable storage. Never use hashing alone for passwords (see Key Derivation below).

```csharp
using System.Security.Cryptography;

// Hash a byte array
byte[] data = "Hello, world"u8.ToArray();
byte[] hash = SHA256.HashData(data);

// Hash a stream (efficient for large files)
await using var stream = File.OpenRead("largefile.bin");
byte[] fileHash = await SHA256.HashDataAsync(stream);

// Compare hashes securely (constant-time comparison prevents timing attacks)
bool isEqual = CryptographicOperations.FixedTimeEquals(hash1, hash2);
```

```csharp
// HMAC for authenticated hashing (message authentication codes)
byte[] key = RandomNumberGenerator.GetBytes(32); // 256-bit key
byte[] mac = HMACSHA256.HashData(key, data);

// Verify HMAC
byte[] computedMac = HMACSHA256.HashData(key, receivedData);
if (!CryptographicOperations.FixedTimeEquals(mac, computedMac))
{
    throw new CryptographicException("Message authentication failed");
}
```

---

## Symmetric Encryption (AES-GCM)

AES-GCM is the recommended symmetric encryption for .NET. It provides both confidentiality and authenticity (authenticated encryption with associated data -- AEAD).

```csharp
using System.Security.Cryptography;

public static class AesGcmEncryptor
{
    private const int NonceSize = 12; // 96-bit nonce (required by GCM)
    private const int TagSize = 16;   // 128-bit authentication tag

    public static byte[] Encrypt(byte[] plaintext, byte[] key)
    {
        var nonce = RandomNumberGenerator.GetBytes(NonceSize);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagSize];

        using var aes = new AesGcm(key, TagSize);
        aes.Encrypt(nonce, plaintext, ciphertext, tag);

        // Prepend nonce + append tag for transport
        var result = new byte[NonceSize + ciphertext.Length + TagSize];
        nonce.CopyTo(result, 0);
        ciphertext.CopyTo(result, NonceSize);
        tag.CopyTo(result, NonceSize + ciphertext.Length);
        return result;
    }

    public static byte[] Decrypt(byte[] encryptedData, byte[] key)
    {
        var nonce = encryptedData.AsSpan(0, NonceSize);
        var ciphertext = encryptedData.AsSpan(NonceSize, encryptedData.Length - NonceSize - TagSize);
        var tag = encryptedData.AsSpan(encryptedData.Length - TagSize);
        var plaintext = new byte[ciphertext.Length];

        using var aes = new AesGcm(key, TagSize);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);
        return plaintext;
    }
}
```

```csharp
// ASP.NET Core Data Protection API -- preferred for web application scenarios
// Handles key management, rotation, and storage automatically
using Microsoft.AspNetCore.DataProtection;

public sealed class TokenProtector(IDataProtectionProvider provider)
{
    private readonly IDataProtector _protector =
        provider.CreateProtector("Tokens.V1");

    public string Protect(string plaintext) => _protector.Protect(plaintext);
    public string Unprotect(string ciphertext) => _protector.Unprotect(ciphertext);
}

// Registration:
builder.Services.AddDataProtection()
    .SetApplicationName("MyApp")
    .PersistKeysToFileSystem(new DirectoryInfo("/keys"));
```

---

## Asymmetric Cryptography (RSA, ECDSA)

### RSA

Use RSA for encryption of small payloads (key wrapping) and digital signatures. Minimum 2048-bit keys; prefer 4096-bit for new systems.

```csharp
using System.Security.Cryptography;

// Generate an RSA key pair
using var rsa = RSA.Create(4096);

// Sign data
byte[] signature = rsa.SignData(data, HashAlgorithmName.SHA256, RSASignaturePadding.Pss);

// Verify signature (with public key)
byte[] publicKeyBytes = rsa.ExportRSAPublicKey();
using var rsaPublic = RSA.Create();
rsaPublic.ImportRSAPublicKey(publicKeyBytes, out _);
bool valid = rsaPublic.VerifyData(data, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pss);

// Encrypt with OAEP padding (never use PKCS#1 v1.5 for new code)
byte[] encrypted = rsaPublic.Encrypt(smallPayload, RSAEncryptionPadding.OaepSHA256);
byte[] decrypted = rsa.Decrypt(encrypted, RSAEncryptionPadding.OaepSHA256);
```

### ECDSA

Prefer ECDSA over RSA for digital signatures in new projects -- smaller keys with equivalent security.

```csharp
using System.Security.Cryptography;

// Generate ECDSA key (P-256 = NIST curve, widely supported)
using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);

// Sign data
byte[] signature = ecdsa.SignData(data, HashAlgorithmName.SHA256);

// Export public key for verification
byte[] publicKey = ecdsa.ExportSubjectPublicKeyInfo();

// Import and verify
using var ecdsaPublic = ECDsa.Create();
ecdsaPublic.ImportSubjectPublicKeyInfo(publicKey, out _);
bool valid = ecdsaPublic.VerifyData(data, signature, HashAlgorithmName.SHA256);
```

---

## Key Derivation (Password Hashing)

### PBKDF2 (Built-in)

PBKDF2 is built into .NET and acceptable for password hashing. Use at least 600,000 iterations with SHA-256 (OWASP recommendation).

```csharp
using System.Buffers.Binary;
using System.Security.Cryptography;

public static class PasswordHasher
{
    private const int SaltSize = 16;       // 128-bit salt
    private const int HashSize = 32;       // 256-bit derived key
    private const int Iterations = 600_000; // OWASP 2023 recommendation for SHA-256
    private const int PayloadSize = 4 + SaltSize + HashSize; // iteration count + salt + hash

    public static string HashPassword(string password)
    {
        byte[] salt = RandomNumberGenerator.GetBytes(SaltSize);
        byte[] hash = Rfc2898DeriveBytes.Pbkdf2(
            password,
            salt,
            Iterations,
            HashAlgorithmName.SHA256,
            HashSize);

        // Store iteration count (fixed little-endian), salt, and hash together
        byte[] result = new byte[PayloadSize];
        BinaryPrimitives.WriteInt32LittleEndian(result, Iterations);
        salt.CopyTo(result.AsSpan(4));
        hash.CopyTo(result.AsSpan(4 + SaltSize));
        return Convert.ToBase64String(result);
    }

    public static bool VerifyPassword(string password, string stored)
    {
        // Defensive parsing: reject malformed input without exceptions
        Span<byte> decoded = stackalloc byte[PayloadSize];
        if (!Convert.TryFromBase64String(stored, decoded, out int bytesWritten)
            || bytesWritten != PayloadSize)
        {
            return false;
        }

        int iterations = BinaryPrimitives.ReadInt32LittleEndian(decoded);
        if (iterations <= 0)
            return false;

        var salt = decoded.Slice(4, SaltSize);
        var expectedHash = decoded.Slice(4 + SaltSize, HashSize);

        byte[] actualHash = Rfc2898DeriveBytes.Pbkdf2(
            password,
            salt,
            iterations,
            HashAlgorithmName.SHA256,
            HashSize);

        return CryptographicOperations.FixedTimeEquals(expectedHash, actualHash);
    }
}
```

### Argon2 (via NuGet)

Argon2id is the recommended algorithm for password hashing when a NuGet dependency is acceptable. It is memory-hard, resisting GPU/ASIC attacks better than PBKDF2.

```csharp
// Requires: <PackageReference Include="Konscious.Security.Cryptography.Argon2" Version="1.*" />
using Konscious.Security.Cryptography;

public static byte[] HashWithArgon2(string password, byte[] salt)
{
    using var argon2 = new Argon2id(Encoding.UTF8.GetBytes(password))
    {
        Salt = salt,
        DegreeOfParallelism = 4,  // threads
        MemorySize = 65536,       // 64 MB
        Iterations = 3
    };
    return argon2.GetBytes(32); // 256-bit hash
}
```

> Prefer ASP.NET Core Identity's `PasswordHasher<T>` for web applications -- it handles PBKDF2 with correct parameters and format versioning automatically. Use custom hashing only for non-Identity scenarios.

---

## Post-Quantum Cryptography (.NET 10+)

.NET 10 introduces post-quantum cryptography (PQC) through the `System.Security.Cryptography` namespace. These algorithms resist attacks from both classical and quantum computers.

### Platform Requirements

PQC APIs require OS-level support:
- **Windows:** Windows 11 (November 2025 update) or Windows Server 2025 with PQC updates
- **Linux/macOS:** OpenSSL 3.5 or newer

Always check `IsSupported` before using PQC types. On unsupported platforms, fall back to classical algorithms.

### ML-KEM (FIPS 203) -- Key Encapsulation

ML-KEM replaces classical key exchange (ECDH) for establishing shared secrets. It is the most mature .NET 10 PQC API (not marked `[Experimental]` at class level).

```csharp
#if NET10_0_OR_GREATER
using System.Security.Cryptography;

if (!MLKem.IsSupported)
{
    Console.WriteLine("ML-KEM not available on this platform");
    return;
}

// Generate a key pair
using MLKem privateKey = MLKem.GenerateKey(MLKemAlgorithm.MLKem768);

// Export public encapsulation key (share with peer)
byte[] publicKeyBytes = privateKey.ExportEncapsulationKey();

// Peer: import public key and encapsulate a shared secret
using MLKem publicKey = MLKem.ImportEncapsulationKey(
    MLKemAlgorithm.MLKem768, publicKeyBytes);
publicKey.Encapsulate(out byte[] ciphertext, out byte[] sharedSecret1);

// Original holder: decapsulate to recover the same shared secret
byte[] sharedSecret2 = privateKey.Decapsulate(ciphertext);

// Both parties now have the same shared secret for symmetric encryption
bool match = sharedSecret1.AsSpan().SequenceEqual(sharedSecret2);
#endif
```

**Parameter sets:**

| Parameter Set | Security Level | Encapsulation Key | Ciphertext |
|---|---|---|---|
| `MLKemAlgorithm.MLKem512` | NIST Level 1 (128-bit) | 800 bytes | 768 bytes |
| `MLKemAlgorithm.MLKem768` | NIST Level 3 (192-bit) | 1,184 bytes | 1,088 bytes |
| `MLKemAlgorithm.MLKem1024` | NIST Level 5 (256-bit) | 1,568 bytes | 1,568 bytes |

Prefer `MLKem768` for general use (balances security and performance).

### ML-DSA (FIPS 204) -- Digital Signatures

ML-DSA replaces RSA/ECDSA for quantum-resistant digital signatures.

```csharp
#if NET10_0_OR_GREATER
using System.Security.Cryptography;

if (!MLDsa.IsSupported)
{
    Console.WriteLine("ML-DSA not available on this platform");
    return;
}

// Generate signing key
using MLDsa key = MLDsa.GenerateKey(MLDsaAlgorithm.MLDsa65);

// Sign data
byte[] data = "Document to sign"u8.ToArray();
byte[] signature = new byte[key.Algorithm.SignatureSizeInBytes];
key.SignData(data, signature);

// Export public key for verification
byte[] publicKeyBytes = key.ExportMLDsaPublicKey();

// Verify with public key
using MLDsa publicKey = MLDsa.ImportMLDsaPublicKey(
    MLDsaAlgorithm.MLDsa65, publicKeyBytes);
bool valid = publicKey.VerifyData(data, signature);
#endif
```

**Parameter sets:**

| Parameter Set | Security Level | Public Key | Signature |
|---|---|---|---|
| `MLDsaAlgorithm.MLDsa44` | NIST Level 2 | 1,312 bytes | 2,420 bytes |
| `MLDsaAlgorithm.MLDsa65` | NIST Level 3 | 1,952 bytes | 3,309 bytes |
| `MLDsaAlgorithm.MLDsa87` | NIST Level 5 | 2,592 bytes | 4,627 bytes |

### SLH-DSA (FIPS 205) -- Hash-Based Signatures

SLH-DSA (Stateless Hash-Based Digital Signature Algorithm) provides extremely conservative long-term signatures. Use when mathematical structure of lattice-based schemes (ML-DSA) is a concern. The entire `SlhDsa` class is `[Experimental]` (SYSLIB5006) -- Windows has not yet added native support.

```csharp
#if NET10_0_OR_GREATER
using System.Security.Cryptography;

// SlhDsa is [Experimental] -- suppress SYSLIB5006 only when intentional
#pragma warning disable SYSLIB5006
if (SlhDsa.IsSupported)
{
    using SlhDsa key = SlhDsa.GenerateKey(SlhDsaAlgorithm.SlhDsaSha2_128s);
    byte[] data = "Long-term document"u8.ToArray();
    byte[] signature = new byte[key.Algorithm.SignatureSizeInBytes];
    key.SignData(data, signature);
    bool valid = key.VerifyData(data, signature);
}
#pragma warning restore SYSLIB5006
#endif
```

### Fallback Strategy for net8.0/net9.0

Post-quantum algorithms are only available in .NET 10+. For applications targeting earlier TFMs:

1. **Use classical algorithms now:** ECDSA (P-256/P-384) for signatures, ECDH + AES-GCM for key exchange/encryption. These remain secure against classical attacks.
2. **Prepare for migration:** Isolate cryptographic operations behind interfaces so algorithm swaps require minimal code changes.
3. **Multi-target when ready:** Use `#if NET10_0_OR_GREATER` conditionals or separate assemblies per TFM to add PQC support alongside classical fallbacks.
4. **Harvest-now-decrypt-later:** For data that must remain confidential for 10+ years, consider migrating to .NET 10 sooner to protect against future quantum decryption of captured ciphertext.

### Interoperability Caveats

- **Key and signature sizes:** PQC keys and signatures are significantly larger than classical equivalents (e.g., ML-DSA-65 signature is 3,309 bytes vs ECDSA P-256 at 64 bytes). This affects storage, bandwidth, and protocol message sizes.
- **No cross-platform PQC yet:** PQC APIs depend on OS crypto libraries. An app compiled for net10.0 will fail at runtime on older OS versions. Always gate behind `IsSupported`.
- **PKCS#8/X.509 formats are experimental:** Import/export of PQC keys in standard certificate formats is `[Experimental]` pending IETF RFC finalization. Do not persist PQC keys in PKCS#8 format in production yet.
- **Composite/hybrid signatures:** `CompositeMLDsa` (hybrid ML-DSA + classical) is fully `[Experimental]` with no native OS support. Use it only for prototyping.
- **TLS integration:** ML-DSA and SLH-DSA certificates work in TLS 1.3+ via `SslStream`, but only when the OS crypto library supports PQC in TLS. Verify with your deployment target.
- **Performance:** ML-KEM and ML-DSA are fast. SLH-DSA is significantly slower for signing (seconds, not milliseconds) -- use it only when hash-based security guarantees are required.

---

## Deprecated Cryptographic APIs

The following cryptographic algorithms are broken or obsolete. Do not use them in new code.

| Algorithm | Replacement | Reason |
|---|---|---|
| MD5 | SHA-256+ | Collision attacks since 2004; trivially broken |
| SHA-1 | SHA-256+ | Collision attacks demonstrated (SHAttered, 2017) |
| DES | AES-GCM | 56-bit key; brute-forceable in hours |
| 3DES (TripleDES) | AES-GCM | Deprecated by NIST (2023); Sweet32 attack |
| RC2 | AES-GCM | Weak key schedule; effective key length < advertised |
| RSA PKCS#1 v1.5 encryption | RSA-OAEP | Bleichenbacher padding oracle attacks |

For the full list of deprecated security patterns beyond cryptography (CAS, APTCA, .NET Remoting, DCOM, BinaryFormatter), see [skill:dotnet-api] which is the canonical owner of deprecated security pattern warnings.

---

## Agent Gotchas

1. **Never reuse a nonce with AES-GCM** -- reusing a nonce with the same key breaks both confidentiality and authenticity. Always generate a fresh random nonce per encryption operation.
2. **Never use ECB mode** -- ECB encrypts identical plaintext blocks to identical ciphertext blocks, leaking patterns. .NET's `Aes.Create()` defaults to CBC, but prefer AES-GCM for authenticated encryption.
3. **Never compare hashes with `==`** -- use `CryptographicOperations.FixedTimeEquals` to prevent timing side-channel attacks.
4. **Never use MD5 or SHA-1 for security purposes** -- they are broken. SHA-1 is acceptable only for non-security checksums (e.g., git object hashes) where collision resistance is not a security requirement.
5. **Never hardcode encryption keys** -- use [skill:dotnet-api] for key storage. Generate keys with `RandomNumberGenerator.GetBytes`.
6. **Minimum RSA key size is 2048 bits** -- NIST deprecated 1024-bit RSA keys. Use 4096 for new systems.
7. **PBKDF2 iteration count must be high** -- OWASP recommends 600,000 iterations with SHA-256 (as of 2023). Lower counts are brute-forceable.
8. **PQC `IsSupported` checks are mandatory** -- calling PQC APIs on unsupported platforms throws `PlatformNotSupportedException`. Always check before use.
9. **Do not suppress SYSLIB5006 globally** -- suppress the experimental diagnostic only at the specific call site where you intentionally use experimental PQC APIs.

---

## References

- [ASP.NET Core Security](https://learn.microsoft.com/en-us/aspnet/core/security/?view=aspnetcore-10.0)
- [Security in .NET](https://learn.microsoft.com/en-us/dotnet/standard/security/)
- [Secure Coding Guidelines for .NET](https://learn.microsoft.com/en-us/dotnet/standard/security/secure-coding-guidelines)
- [Cryptography Model in .NET](https://learn.microsoft.com/en-us/dotnet/standard/security/cryptography-model)
- [Post-Quantum Cryptography in .NET](https://devblogs.microsoft.com/dotnet/post-quantum-cryptography-in-dotnet/)
- [ASP.NET Core Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction?view=aspnetcore-10.0)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [NIST FIPS 203 (ML-KEM)](https://csrc.nist.gov/pubs/fips/203/final)
- [NIST FIPS 204 (ML-DSA)](https://csrc.nist.gov/pubs/fips/204/final)
- [NIST FIPS 205 (SLH-DSA)](https://csrc.nist.gov/pubs/fips/205/final)
