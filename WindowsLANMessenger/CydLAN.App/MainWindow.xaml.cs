using CydLAN.Networking;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using System.Collections.ObjectModel;
using Windows.Graphics;

namespace CydLAN.App;

public sealed partial class MainWindow : Window
{
    private readonly LmcDiscoveryService _discovery = new();
    private readonly Dictionary<string, LanUserItem> _usersById = new(StringComparer.Ordinal);

    public ObservableCollection<LanUserItem> Users { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        ConfigureWindow();
        UsersList.ItemsSource = Users;

        _discovery.PeerAnnounced += Discovery_PeerAnnounced;
        _discovery.PeerDeparted += Discovery_PeerDeparted;
        _discovery.Error += Discovery_Error;
        Closed += MainWindow_Closed;

        _ = InitializeDiscoveryAsync();
    }

    private void ConfigureWindow()
    {
        ExtendsContentIntoTitleBar = true;
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

    private async Task InitializeDiscoveryAsync()
    {
        try
        {
            await _discovery.StartAsync();

            if (_discovery.Adapter is not null && _discovery.LocalUserId is not null)
            {
                AddOrUpdateUser(new LanUserItem(
                    _discovery.LocalUserId,
                    "Cyd (You)",
                    "Online",
                    _discovery.Adapter.Address.ToString(),
                    "CY",
                    "#31C96B",
                    0));
            }
        }
        catch (Exception exception)
        {
            ShowDiscoveryError(exception.Message);
        }
    }

    private void Discovery_PeerAnnounced(object? sender, LmcPeerAnnouncement peer)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            var initials = peer.Address.Split('.') is { Length: > 0 } parts
                ? $"L{parts[^1]}"
                : "LAN";

            AddOrUpdateUser(new LanUserItem(
                peer.UserId,
                $"LAN User · {peer.Address}",
                "Online",
                $"LANNIES peer · {peer.Address}",
                initials,
                "#31C96B",
                0));
        });
    }

    private void Discovery_PeerDeparted(object? sender, LmcPeerAnnouncement peer)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_usersById.Remove(peer.UserId, out var user))
            {
                return;
            }

            Users.Remove(user);
        });
    }

    private void Discovery_Error(object? sender, Exception exception)
    {
        DispatcherQueue.TryEnqueue(() => ShowDiscoveryError(exception.Message));
    }

    private void AddOrUpdateUser(LanUserItem user)
    {
        if (_usersById.ContainsKey(user.UserId))
        {
            return;
        }

        _usersById.Add(user.UserId, user);
        Users.Add(user);
    }

    private void ShowDiscoveryError(string message)
    {
        ChatName.Text = "LAN discovery unavailable";
        ChatStatus.Text = message;
        ChatStatus.Foreground = new SolidColorBrush(ColorHelper.FromArgb(255, 231, 184, 75));
    }

    private async void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _discovery.PeerAnnounced -= Discovery_PeerAnnounced;
        _discovery.PeerDeparted -= Discovery_PeerDeparted;
        _discovery.Error -= Discovery_Error;
        await _discovery.DisposeAsync();
    }

    private void UsersList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not LanUserItem user)
        {
            return;
        }

        ChatName.Text = user.Name;
        ChatStatus.Text = user.Status;
        ChatStatus.Foreground = user.StatusBrush;
    }
}

public sealed class LanUserItem
{
    public LanUserItem(
        string userId,
        string name,
        string status,
        string device,
        string initials,
        string statusColor,
        int unreadCount)
    {
        UserId = userId;
        Name = name;
        Status = status;
        Device = device;
        Initials = initials;
        StatusBrush = new SolidColorBrush(ColorHelper.FromArgb(
            255,
            Convert.ToByte(statusColor.Substring(1, 2), 16),
            Convert.ToByte(statusColor.Substring(3, 2), 16),
            Convert.ToByte(statusColor.Substring(5, 2), 16)));
        UnreadCount = unreadCount;
        UnreadVisibility = unreadCount > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    public string UserId { get; }
    public string Name { get; }
    public string Status { get; }
    public string Device { get; }
    public string Initials { get; }
    public Brush StatusBrush { get; }
    public int UnreadCount { get; }
    public Visibility UnreadVisibility { get; }
}
