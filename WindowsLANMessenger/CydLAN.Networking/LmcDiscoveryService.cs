using CydLAN.Protocol;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace CydLAN.Networking;

public sealed record LmcPeerAnnouncement(
    string UserId,
    string Address,
    long MessageId,
    string Type,
    DateTimeOffset SeenAt);

public sealed class LmcDiscoveryService : IAsyncDisposable
{
    public const int DefaultUdpPort = 50000;
    public static readonly IPAddress DefaultMulticastAddress = IPAddress.Parse("239.255.100.100");

    private readonly int _port;
    private readonly IPAddress _multicastAddress;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private UdpClient? _receiver;
    private UdpClient? _sender;
    private Task? _receiveLoop;
    private NetworkAdapterInfo? _adapter;
    private string? _localUserId;
    private long _messageId = 1;

    public event EventHandler<LmcPeerAnnouncement>? PeerAnnounced;
    public event EventHandler<LmcPeerAnnouncement>? PeerDeparted;
    public event EventHandler<Exception>? Error;

    public LmcDiscoveryService(int port = DefaultUdpPort, IPAddress? multicastAddress = null)
    {
        _port = port;
        _multicastAddress = multicastAddress ?? DefaultMulticastAddress;
    }

    public bool IsRunning => _receiveLoop is not null;
    public NetworkAdapterInfo? Adapter => _adapter;
    public string? LocalUserId => _localUserId;

    public async Task StartAsync(string? displayName = null, CancellationToken cancellationToken = default)
    {
        if (IsRunning)
        {
            return;
        }

        _adapter = NetworkAdapterInfo.FindPreferredIpv4()
            ?? throw new InvalidOperationException("No active IPv4 LAN adapter was found.");
        _localUserId = CreateUserId(_adapter.PhysicalAddress, Environment.UserName);

        _receiver = CreateReceiver(_adapter);
        _sender = CreateSender(_adapter);
        _receiveLoop = ReceiveLoopAsync(_shutdown.Token);

        // Upstream sends depart first to clear stale presence, then announce.
        await SendPresenceAsync(ProtocolDefinitions.Message.Depart, cancellationToken).ConfigureAwait(false);
        await SendPresenceAsync(ProtocolDefinitions.Message.Announce, cancellationToken).ConfigureAwait(false);
    }

    public Task RefreshAsync(CancellationToken cancellationToken = default) =>
        SendPresenceAsync(ProtocolDefinitions.Message.Announce, cancellationToken);

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        if (!IsRunning)
        {
            return;
        }

        try
        {
            await SendPresenceAsync(ProtocolDefinitions.Message.Depart, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Error?.Invoke(this, exception);
        }

        _shutdown.Cancel();
        _receiver?.Dispose();
        _sender?.Dispose();

        if (_receiveLoop is not null)
        {
            try
            {
                await _receiveLoop.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
            catch (ObjectDisposedException)
            {
            }
        }

        _receiveLoop = null;
    }

    private UdpClient CreateReceiver(NetworkAdapterInfo adapter)
    {
        var client = new UdpClient(AddressFamily.InterNetwork);
        client.Client.ExclusiveAddressUse = false;
        client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        client.Client.Bind(new IPEndPoint(IPAddress.Any, _port));
        client.JoinMulticastGroup(_multicastAddress, adapter.Address);
        return client;
    }

    private UdpClient CreateSender(NetworkAdapterInfo adapter)
    {
        var client = new UdpClient(AddressFamily.InterNetwork);
        client.EnableBroadcast = true;
        client.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface, adapter.Address.GetAddressBytes());
        client.MulticastLoopback = false;
        return client;
    }

    private async Task SendPresenceAsync(string messageType, CancellationToken cancellationToken)
    {
        if (_sender is null || _adapter is null || string.IsNullOrWhiteSpace(_localUserId))
        {
            throw new InvalidOperationException("Discovery service has not been started.");
        }

        await _sendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var xml = LmcMessageCodec.Create(messageType, _messageId++, _localUserId).Serialize();
            var payload = Encoding.UTF8.GetBytes(xml);

            await _sender.SendAsync(payload, new IPEndPoint(_multicastAddress, _port), cancellationToken)
                .ConfigureAwait(false);
            await _sender.SendAsync(payload, new IPEndPoint(_adapter.DirectedBroadcast, _port), cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            _sendGate.Release();
        }
    }

    private async Task ReceiveLoopAsync(CancellationToken cancellationToken)
    {
        if (_receiver is null)
        {
            return;
        }

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var received = await _receiver.ReceiveAsync(cancellationToken).ConfigureAwait(false);
                var xml = Encoding.UTF8.GetString(received.Buffer);
                if (!LmcMessageCodec.TryRead(xml, out var header, out _)
                    || header is null
                    || string.Equals(header.From, _localUserId, StringComparison.Ordinal))
                {
                    continue;
                }

                var announcement = new LmcPeerAnnouncement(
                    header.From,
                    received.RemoteEndPoint.Address.ToString(),
                    header.MessageId,
                    header.Type,
                    DateTimeOffset.UtcNow);

                if (header.Type == ProtocolDefinitions.Message.Announce)
                {
                    PeerAnnounced?.Invoke(this, announcement);
                }
                else if (header.Type == ProtocolDefinitions.Message.Depart)
                {
                    PeerDeparted?.Invoke(this, announcement);
                }
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

    public static string CreateUserId(System.Net.NetworkInformation.PhysicalAddress physicalAddress, string logonName)
    {
        ArgumentNullException.ThrowIfNull(physicalAddress);
        ArgumentException.ThrowIfNullOrWhiteSpace(logonName);
        return $"{physicalAddress}{logonName}".Replace(":", string.Empty, StringComparison.Ordinal);
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        _shutdown.Dispose();
        _sendGate.Dispose();
    }
}
