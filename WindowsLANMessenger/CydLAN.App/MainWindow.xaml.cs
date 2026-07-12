using CydLAN.Networking;
using CydLAN.Protocol;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using System.Collections.ObjectModel;
using Windows.Graphics;
using Windows.System;

namespace CydLAN.App;

public sealed partial class MainWindow : Window
{
    private readonly LmcDiscoveryService _discovery = new();
    private readonly LmcTcpService _tcp = new();
    private readonly Dictionary<string, LanUserItem> _usersById = new(StringComparer.Ordinal);
    private long _messageId = 1;
    private LanUserItem? _selectedUser;

    public ObservableCollection<LanUserItem> Users { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        ConfigureWindow();
        UsersList.ItemsSource = Users;

        _discovery.PeerAnnounced += Discovery_PeerAnnounced;
        _discovery.PeerDeparted += Discovery_PeerDeparted;
        _discovery.Error += Service_Error;
        _tcp.SecurePeerConnected += Tcp_SecurePeerConnected;
        _tcp.PeerDisconnected += Tcp_PeerDisconnected;
        _tcp.MessageReceived += Tcp_MessageReceived;
        _tcp.Error += Service_Error;
        Closed += MainWindow_Closed;

        _ = InitializeServicesAsync();
    }

    private void ConfigureWindow()
    {
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Resize(new SizeInt32(1280, 780));

        if (MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
        }

        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = 960;
            presenter.PreferredMinimumHeight = 600;
        }
    }

    private async Task InitializeServicesAsync()
    {
        try
        {
            await _discovery.StartAsync();
            if (_discovery.Adapter is null || _discovery.LocalUserId is null)
            {
                throw new InvalidOperationException("Discovery did not resolve a local LAN identity.");
            }

            await _tcp.StartAsync(_discovery.LocalUserId);
            ConnectionAddress.Text = $"{_discovery.Adapter.Address} · UDP/TCP 50000";
            AddOrUpdateUser(new LanUserItem(
                _discovery.LocalUserId,
                "Cyd (You)",
                "Online",
                _discovery.Adapter.Address.ToString(),
                "CY",
                "#31C96B",
                0,
                true));
            ChatStatus.Text = "Discovery and secure transport active";
        }
        catch (Exception exception)
        {
            ShowServiceError(exception.Message);
        }
    }

    private void Discovery_PeerAnnounced(object? sender, LmcPeerAnnouncement peer)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            var parts = peer.Address.Split('.');
            var initials = parts.Length > 0 ? $"L{parts[^1]}" : "LAN";
            AddOrUpdateUser(new LanUserItem(
                peer.UserId,
                $"LAN User · {peer.Address}",
                "Connecting securely",
                peer.Address,
                initials,
                "#E7B84B",
                0,
                false));
        });

        _ = ConnectPeerAsync(peer);
    }

    private async Task ConnectPeerAsync(LmcPeerAnnouncement peer)
    {
        try
        {
            await _tcp.ConnectAsync(peer.UserId, peer.Address);
        }
        catch (Exception exception)
        {
            Service_Error(this, exception);
        }
    }

    private void Discovery_PeerDeparted(object? sender, LmcPeerAnnouncement peer)
    {
        DispatcherQueue.TryEnqueue(() => RemoveUser(peer.UserId));
    }

    private void Tcp_SecurePeerConnected(object? sender, LmcSecurePeer peer)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_usersById.TryGetValue(peer.UserId, out var existing))
            {
                existing.SetSecure();
                UsersList.ItemsSource = null;
                UsersList.ItemsSource = Users;
            }

            if (_selectedUser?.UserId == peer.UserId)
            {
                ChatStatus.Text = "Encrypted · RSA OAEP + AES-256-CBC";
                SecurityText.Text = "Secure session established with legacy-compatible RSA OAEP and AES-256-CBC.";
                SendButton.IsEnabled = true;
            }
        });

        _ = SendUserDataAsync(peer);
    }

    private async Task SendUserDataAsync(LmcSecurePeer peer)
    {
        try
        {
            var message = new LmcXmlMessage()
                .AddData(LmcXmlNode.UserId, _discovery.LocalUserId)
                .AddData(LmcXmlNode.Name, Environment.UserName)
                .AddData(LmcXmlNode.Address, _discovery.Adapter?.Address.ToString())
                .AddData(LmcXmlNode.Version, ProtocolDefinitions.UpstreamVersion)
                .AddData(LmcXmlNode.Status, ProtocolDefinitions.Status.Available)
                .AddData(LmcXmlNode.Note, "CydLAN Messenger")
                .AddData(LmcXmlNode.UserCapabilities, ((uint)(ProtocolDefinitions.UserCapabilities.File | ProtocolDefinitions.UserCapabilities.GroupMessage)).ToString())
                .AddData("queryop", "get");
            var xml = LmcMessageCodec.Create(
                ProtocolDefinitions.Message.UserData,
                _messageId++,
                _discovery.LocalUserId!,
                peer.UserId,
                message).Serialize();
            await _tcp.SendXmlAsync(peer.UserId, xml);
        }
        catch (Exception exception)
        {
            Service_Error(this, exception);
        }
    }

    private void Tcp_PeerDisconnected(object? sender, LmcSecurePeer peer)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_usersById.TryGetValue(peer.UserId, out var existing))
            {
                existing.SetDisconnected();
                UsersList.ItemsSource = null;
                UsersList.ItemsSource = Users;
            }
            if (_selectedUser?.UserId == peer.UserId)
            {
                SendButton.IsEnabled = false;
                ChatStatus.Text = "Disconnected";
            }
        });
    }

    private void Tcp_MessageReceived(object? sender, LmcEncryptedMessage incoming)
    {
        if (!LmcMessageCodec.TryRead(incoming.Xml, out var header, out var message)
            || header is null || message is null)
        {
            return;
        }

        if (header.Type == ProtocolDefinitions.Message.Direct)
        {
            var text = message.Data(LmcXmlNode.Message) ?? string.Empty;
            DispatcherQueue.TryEnqueue(() => AddMessageBubble(text, false));
        }
        else if (header.Type == ProtocolDefinitions.Message.UserData)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                if (_usersById.TryGetValue(incoming.UserId, out var user))
                {
                    user.UpdateIdentity(
                        message.Data(LmcXmlNode.Name) ?? user.Name,
                        message.Data(LmcXmlNode.Status) ?? ProtocolDefinitions.Status.Available);
                    UsersList.ItemsSource = null;
                    UsersList.ItemsSource = Users;
                }
            });
        }
    }

    private async Task SendCurrentMessageAsync()
    {
        var text = MessageInput.Text.Trim();
        var peer = _selectedUser;
        if (peer is null || peer.IsLocal || !peer.IsSecure || string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        try
        {
            var body = new LmcXmlMessage().AddData(LmcXmlNode.Message, text);
            var xml = LmcMessageCodec.Create(
                ProtocolDefinitions.Message.Direct,
                _messageId++,
                _discovery.LocalUserId!,
                peer.UserId,
                body).Serialize();
            await _tcp.SendXmlAsync(peer.UserId, xml);
            AddMessageBubble(text, true);
            MessageInput.Text = string.Empty;
        }
        catch (Exception exception)
        {
            ShowServiceError(exception.Message);
        }
    }

    private void AddMessageBubble(string text, bool outgoing)
    {
        var bubble = new Border
        {
            Background = new SolidColorBrush(outgoing
                ? ColorHelper.FromArgb(255, 23, 72, 160)
                : ColorHelper.FromArgb(255, 24, 36, 51)),
            CornerRadius = new CornerRadius(5),
            Padding = new Thickness(12, 9, 12, 9),
            HorizontalAlignment = outgoing ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            MaxWidth = 520,
            Child = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap }
        };
        MessagesPanel.Children.Add(bubble);
    }

    private void SendButton_Click(object sender, RoutedEventArgs e) => _ = SendCurrentMessageAsync();

    private void MessageInput_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter)
        {
            e.Handled = true;
            _ = SendCurrentMessageAsync();
        }
    }

    private void Service_Error(object? sender, Exception exception)
    {
        DispatcherQueue.TryEnqueue(() => ShowServiceError(exception.Message));
    }

    private void AddOrUpdateUser(LanUserItem user)
    {
        if (_usersById.ContainsKey(user.UserId))
        {
            return;
        }
        _usersById.Add(user.UserId, user);
        Users.Add(user);
        UpdateUserCounts();
    }

    private void RemoveUser(string userId)
    {
        if (!_usersById.Remove(userId, out var user))
        {
            return;
        }
        Users.Remove(user);
        if (_selectedUser?.UserId == userId)
        {
            _selectedUser = null;
            SendButton.IsEnabled = false;
        }
        UpdateUserCounts();
    }

    private void UpdateUserCounts()
    {
        var online = Users.Count(user => user.Status != "Disconnected");
        AllFilter.Content = $"All ({Users.Count})";
        OnlineFilter.Content = $"Online ({online})";
        OnlineCount.Text = $"{online} online";
    }

    private void ShowServiceError(string message)
    {
        ChatName.Text = "LAN service issue";
        ChatStatus.Text = message;
        ChatStatus.Foreground = new SolidColorBrush(ColorHelper.FromArgb(255, 231, 184, 75));
    }

    private async void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _discovery.PeerAnnounced -= Discovery_PeerAnnounced;
        _discovery.PeerDeparted -= Discovery_PeerDeparted;
        _discovery.Error -= Service_Error;
        _tcp.SecurePeerConnected -= Tcp_SecurePeerConnected;
        _tcp.PeerDisconnected -= Tcp_PeerDisconnected;
        _tcp.MessageReceived -= Tcp_MessageReceived;
        _tcp.Error -= Service_Error;
        await _discovery.DisposeAsync();
        await _tcp.DisposeAsync();
    }

    private void UsersList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not LanUserItem user)
        {
            return;
        }

        _selectedUser = user;
        ChatName.Text = user.Name;
        ChatStatus.Text = user.Status;
        ChatStatus.Foreground = user.StatusBrush;
        PeerIdText.Text = user.UserId;
        PeerAddressText.Text = user.Device;
        SecurityText.Text = user.IsSecure
            ? "Secure session established with RSA OAEP and AES-256-CBC."
            : "Secure handshake is still in progress.";
        SendButton.IsEnabled = user.IsSecure && !user.IsLocal;
    }
}

public sealed class LanUserItem
{
    public LanUserItem(string userId, string name, string status, string device, string initials, string statusColor, int unreadCount, bool isLocal)
    {
        UserId = userId;
        Name = name;
        Status = status;
        Device = device;
        Initials = initials;
        IsLocal = isLocal;
        StatusBrush = CreateBrush(statusColor);
        UnreadCount = unreadCount;
        UnreadVisibility = unreadCount > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    public string UserId { get; }
    public string Name { get; private set; }
    public string Status { get; private set; }
    public string Device { get; }
    public string Initials { get; }
    public Brush StatusBrush { get; private set; }
    public int UnreadCount { get; }
    public Visibility UnreadVisibility { get; }
    public bool IsLocal { get; }
    public bool IsSecure { get; private set; }

    public void SetSecure()
    {
        IsSecure = true;
        Status = "Encrypted";
        StatusBrush = CreateBrush("#31C96B");
    }

    public void SetDisconnected()
    {
        IsSecure = false;
        Status = "Disconnected";
        StatusBrush = CreateBrush("#7F8997");
    }

    public void UpdateIdentity(string name, string status)
    {
        Name = name;
        Status = status == ProtocolDefinitions.Status.Available ? "Encrypted" : status;
    }

    private static Brush CreateBrush(string color) => new SolidColorBrush(ColorHelper.FromArgb(
        255,
        Convert.ToByte(color.Substring(1, 2), 16),
        Convert.ToByte(color.Substring(3, 2), 16),
        Convert.ToByte(color.Substring(5, 2), 16)));
}
