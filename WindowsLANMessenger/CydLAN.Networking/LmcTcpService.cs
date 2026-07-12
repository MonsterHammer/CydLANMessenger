using CydLAN.Protocol;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace CydLAN.Networking;

public sealed record LmcSecurePeer(string UserId, string Address);
public sealed record LmcEncryptedMessage(string UserId, string Address, string Xml);

public sealed class LmcTcpService : IAsyncDisposable
{
    public const int DefaultTcpPort = 50000;

    private sealed class PeerConnection : IAsyncDisposable
    {
        public required string UserId { get; init; }
        public required string Address { get; init; }
        public required TcpClient Client { get; init; }
        public required NetworkStream Stream { get; init; }
        public SemaphoreSlim SendGate { get; } = new(1, 1);

        public async ValueTask DisposeAsync()
        {
            SendGate.Dispose();
            await Stream.DisposeAsync().ConfigureAwait(false);
            Client.Dispose();
        }
    }

    private readonly int _port;
    private readonly LmcCryptoService _crypto = new();
    private readonly ConcurrentDictionary<string, PeerConnection> _peers = new(StringComparer.Ordinal);
    private readonly CancellationTokenSource _shutdown = new();
    private TcpListener? _listener;
    private Task? _acceptLoop;
    private string? _localUserId;

    public event EventHandler<LmcSecurePeer>? SecurePeerConnected;
    public event EventHandler<LmcSecurePeer>? PeerDisconnected;
    public event EventHandler<LmcEncryptedMessage>? MessageReceived;
    public event EventHandler<Exception>? Error;

    public LmcTcpService(int port = DefaultTcpPort)
    {
        _port = port;
    }

    public bool IsRunning => _acceptLoop is not null;

    public Task StartAsync(string localUserId, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(localUserId);
        if (IsRunning)
        {
            return Task.CompletedTask;
        }

        _localUserId = localUserId;
        _listener = new TcpListener(IPAddress.Any, _port);
        _listener.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        _listener.Start();
        _acceptLoop = AcceptLoopAsync(_shutdown.Token);
        return Task.CompletedTask;
    }

    public async Task ConnectAsync(string peerId, string address, CancellationToken cancellationToken = default)
    {
        EnsureStarted();
        if (peerId == _localUserId || _peers.ContainsKey(peerId))
        {
            return;
        }

        var client = new TcpClient(AddressFamily.InterNetwork);
        try
        {
            await client.ConnectAsync(IPAddress.Parse(address), _port, cancellationToken).ConfigureAwait(false);
            var stream = client.GetStream();
            var identity = Encoding.UTF8.GetBytes("MSG" + _localUserId);
            await stream.WriteAsync(identity, cancellationToken).ConfigureAwait(false);

            var peer = new PeerConnection
            {
                UserId = peerId,
                Address = address,
                Client = client,
                Stream = stream
            };
            if (!_peers.TryAdd(peerId, peer))
            {
                await peer.DisposeAsync().ConfigureAwait(false);
                return;
            }

            _ = ReadLoopAsync(peer, _shutdown.Token);
        }
        catch
        {
            client.Dispose();
            throw;
        }
    }

    public async Task SendXmlAsync(string peerId, string xml, CancellationToken cancellationToken = default)
    {
        if (!_peers.TryGetValue(peerId, out var peer))
        {
            throw new InvalidOperationException($"Peer '{peerId}' is not connected.");
        }
        if (!_crypto.HasSession(peerId))
        {
            throw new InvalidOperationException($"Peer '{peerId}' has not completed the encrypted handshake.");
        }

        var cipher = _crypto.Encrypt(peerId, Encoding.UTF8.GetBytes(xml));
        var datagram = LmcDatagramCodec.Encode(LmcDatagramType.Message, cipher);
        await WriteFrameAsync(peer, datagram, cancellationToken).ConfigureAwait(false);
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested && _listener is not null)
        {
            try
            {
                var client = await _listener.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
                _ = InitializeIncomingAsync(client, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                Error?.Invoke(this, exception);
            }
        }
    }

    private async Task InitializeIncomingAsync(TcpClient client, CancellationToken cancellationToken)
    {
        try
        {
            var stream = client.GetStream();
            var identityBuffer = new byte[64];
            var read = await stream.ReadAsync(identityBuffer, cancellationToken).ConfigureAwait(false);
            if (read <= 3 || !identityBuffer.AsSpan(0, 3).SequenceEqual("MSG"u8))
            {
                client.Dispose();
                return;
            }

            var peerId = Encoding.UTF8.GetString(identityBuffer, 3, read - 3);
            var address = ((IPEndPoint?)client.Client.RemoteEndPoint)?.Address.ToString() ?? string.Empty;
            var peer = new PeerConnection
            {
                UserId = peerId,
                Address = address,
                Client = client,
                Stream = stream
            };

            if (_peers.TryRemove(peerId, out var previous))
            {
                await previous.DisposeAsync().ConfigureAwait(false);
            }
            _peers[peerId] = peer;

            var publicKeyDatagram = LmcDatagramCodec.Encode(LmcDatagramType.PublicKey, _crypto.PublicKeyPem);
            await WriteFrameAsync(peer, publicKeyDatagram, cancellationToken).ConfigureAwait(false);
            await ReadLoopAsync(peer, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            Error?.Invoke(this, exception);
            client.Dispose();
        }
    }

    private async Task ReadLoopAsync(PeerConnection peer, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var frame = await ReadFrameAsync(peer.Stream, cancellationToken).ConfigureAwait(false);
                if (frame is null)
                {
                    break;
                }
                if (!LmcDatagramCodec.TryDecode(frame, out var datagram) || datagram is null)
                {
                    continue;
                }

                switch (datagram.Type)
                {
                    case LmcDatagramType.PublicKey:
                        var encryptedSession = _crypto.CreateEncryptedSession(peer.UserId, datagram.Payload);
                        await WriteFrameAsync(
                            peer,
                            LmcDatagramCodec.Encode(LmcDatagramType.Handshake, encryptedSession),
                            cancellationToken).ConfigureAwait(false);
                        SecurePeerConnected?.Invoke(this, new LmcSecurePeer(peer.UserId, peer.Address));
                        break;

                    case LmcDatagramType.Handshake:
                        _crypto.AcceptEncryptedSession(peer.UserId, datagram.Payload);
                        SecurePeerConnected?.Invoke(this, new LmcSecurePeer(peer.UserId, peer.Address));
                        break;

                    case LmcDatagramType.Message:
                        var clear = _crypto.Decrypt(peer.UserId, datagram.Payload);
                        MessageReceived?.Invoke(this, new LmcEncryptedMessage(
                            peer.UserId,
                            peer.Address,
                            Encoding.UTF8.GetString(clear)));
                        break;
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            Error?.Invoke(this, exception);
        }
        finally
        {
            if (_peers.TryRemove(peer.UserId, out var removed))
            {
                await removed.DisposeAsync().ConfigureAwait(false);
                PeerDisconnected?.Invoke(this, new LmcSecurePeer(peer.UserId, peer.Address));
            }
        }
    }

    private static async Task<byte[]?> ReadFrameAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var lengthBuffer = new byte[4];
        if (!await ReadExactlyOrEndAsync(stream, lengthBuffer, cancellationToken).ConfigureAwait(false))
        {
            return null;
        }

        var length = BinaryPrimitives.ReadUInt32BigEndian(lengthBuffer);
        if (length == 0 || length > 16 * 1024 * 1024)
        {
            throw new InvalidDataException($"Invalid message frame length: {length}.");
        }

        var payload = new byte[length];
        if (!await ReadExactlyOrEndAsync(stream, payload, cancellationToken).ConfigureAwait(false))
        {
            return null;
        }
        return payload;
    }

    private static async Task<bool> ReadExactlyOrEndAsync(NetworkStream stream, Memory<byte> buffer, CancellationToken cancellationToken)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer[offset..], cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                return false;
            }
            offset += read;
        }
        return true;
    }

    private static async Task WriteFrameAsync(PeerConnection peer, byte[] payload, CancellationToken cancellationToken)
    {
        await peer.SendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var length = new byte[4];
            BinaryPrimitives.WriteUInt32BigEndian(length, checked((uint)payload.Length));
            await peer.Stream.WriteAsync(length, cancellationToken).ConfigureAwait(false);
            await peer.Stream.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
            await peer.Stream.FlushAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            peer.SendGate.Release();
        }
    }

    private void EnsureStarted()
    {
        if (!IsRunning || string.IsNullOrWhiteSpace(_localUserId))
        {
            throw new InvalidOperationException("TCP service has not been started.");
        }
    }

    public async ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        _listener?.Stop();
        if (_acceptLoop is not null)
        {
            try { await _acceptLoop.ConfigureAwait(false); }
            catch (OperationCanceledException) { }
        }

        foreach (var peer in _peers.Values)
        {
            await peer.DisposeAsync().ConfigureAwait(false);
        }
        _peers.Clear();
        _crypto.Dispose();
        _shutdown.Dispose();
    }
}
