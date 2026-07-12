using System.Collections.Concurrent;
using System.Security.Cryptography;

namespace CydLAN.Networking;

public sealed class LmcCryptoService : IDisposable
{
    private sealed record Session(byte[] Key, byte[] Iv);

    private readonly RSA _rsa = RSA.Create(1024);
    private readonly ConcurrentDictionary<string, Session> _sessions = new(StringComparer.Ordinal);

    public byte[] PublicKeyPem => System.Text.Encoding.ASCII.GetBytes(
        _rsa.ExportRSAPublicKeyPem().Replace("\r\n", "\n", StringComparison.Ordinal));

    public byte[] CreateEncryptedSession(string peerId, ReadOnlySpan<byte> peerPublicKeyPem)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(peerId);

        using var peerRsa = RSA.Create();
        peerRsa.ImportFromPem(System.Text.Encoding.ASCII.GetString(peerPublicKeyPem));

        var key = RandomNumberGenerator.GetBytes(32);
        var iv = RandomNumberGenerator.GetBytes(16);
        var keyAndIv = new byte[48];
        Buffer.BlockCopy(key, 0, keyAndIv, 0, key.Length);
        Buffer.BlockCopy(iv, 0, keyAndIv, key.Length, iv.Length);

        _sessions[peerId] = new Session(key, iv);
        return peerRsa.Encrypt(keyAndIv, RSAEncryptionPadding.OaepSHA1);
    }

    public void AcceptEncryptedSession(string peerId, ReadOnlySpan<byte> encryptedKeyAndIv)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(peerId);
        var clear = _rsa.Decrypt(encryptedKeyAndIv.ToArray(), RSAEncryptionPadding.OaepSHA1);
        if (clear.Length != 48)
        {
            throw new CryptographicException($"Expected 48 bytes of AES key and IV, received {clear.Length}.");
        }

        _sessions[peerId] = new Session(clear[..32], clear[32..48]);
    }

    public bool HasSession(string peerId) => _sessions.ContainsKey(peerId);

    public byte[] Encrypt(string peerId, ReadOnlySpan<byte> clearData)
    {
        var session = GetSession(peerId);
        using var aes = Aes.Create();
        aes.KeySize = 256;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;
        aes.Key = session.Key;
        aes.IV = session.Iv;
        using var encryptor = aes.CreateEncryptor();
        return encryptor.TransformFinalBlock(clearData.ToArray(), 0, clearData.Length);
    }

    public byte[] Decrypt(string peerId, ReadOnlySpan<byte> cipherData)
    {
        var session = GetSession(peerId);
        using var aes = Aes.Create();
        aes.KeySize = 256;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;
        aes.Key = session.Key;
        aes.IV = session.Iv;
        using var decryptor = aes.CreateDecryptor();
        return decryptor.TransformFinalBlock(cipherData.ToArray(), 0, cipherData.Length);
    }

    private Session GetSession(string peerId) =>
        _sessions.TryGetValue(peerId, out var session)
            ? session
            : throw new InvalidOperationException($"No encrypted session exists for peer '{peerId}'.");

    public void Dispose()
    {
        _rsa.Dispose();
        _sessions.Clear();
    }
}
