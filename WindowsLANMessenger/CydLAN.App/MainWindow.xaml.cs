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
    public ObservableCollection<LanUserItem> Users { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        ConfigureWindow();
        LoadDesignPreviewData();
        UsersList.ItemsSource = Users;
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

    private void LoadDesignPreviewData()
    {
        Users.Add(new LanUserItem("Alex PC", "Online", "Windows 11", "AP", "#31C96B", 2));
        Users.Add(new LanUserItem("Cyd (You)", "Online", "Windows 11", "CY", "#31C96B", 0));
        Users.Add(new LanUserItem("Maya", "Online", "Windows 10", "MY", "#31C96B", 0));
        Users.Add(new LanUserItem("John-Laptop", "Away", "Windows 11", "JL", "#E7B84B", 0));
        Users.Add(new LanUserItem("LANNIE-PC", "Offline", "Last seen 1h ago", "LP", "#7F8997", 0));
        Users.Add(new LanUserItem("OldDesktop", "Offline", "Last seen yesterday", "OD", "#7F8997", 0));
        Users.Add(new LanUserItem("Guest-Node", "Offline", "", "GN", "#7F8997", 0));
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
    public LanUserItem(string name, string status, string device, string initials, string statusColor, int unreadCount)
    {
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

    public string Name { get; }
    public string Status { get; }
    public string Device { get; }
    public string Initials { get; }
    public Brush StatusBrush { get; }
    public int UnreadCount { get; }
    public Visibility UnreadVisibility { get; }
}
