using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace CydLAN.Networking;

public sealed record NetworkAdapterInfo(
    string Name,
    string Description,
    IPAddress Address,
    IPAddress SubnetMask,
    IPAddress DirectedBroadcast,
    PhysicalAddress PhysicalAddress)
{
    public static NetworkAdapterInfo? FindPreferredIpv4()
    {
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.OperationalStatus != OperationalStatus.Up
                || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback)
            {
                continue;
            }

            var properties = adapter.GetIPProperties();
            foreach (var unicast in properties.UnicastAddresses)
            {
                if (unicast.Address.AddressFamily != AddressFamily.InterNetwork
                    || unicast.IPv4Mask is null)
                {
                    continue;
                }

                return new NetworkAdapterInfo(
                    adapter.Name,
                    adapter.Description,
                    unicast.Address,
                    unicast.IPv4Mask,
                    CalculateDirectedBroadcast(unicast.Address, unicast.IPv4Mask),
                    adapter.GetPhysicalAddress());
            }
        }

        return null;
    }

    public static IPAddress CalculateDirectedBroadcast(IPAddress address, IPAddress subnetMask)
    {
        var addressBytes = address.GetAddressBytes();
        var maskBytes = subnetMask.GetAddressBytes();
        if (addressBytes.Length != 4 || maskBytes.Length != 4)
        {
            throw new ArgumentException("IPv4 address and subnet mask are required.");
        }

        var broadcast = new byte[4];
        for (var index = 0; index < 4; index++)
        {
            broadcast[index] = (byte)(addressBytes[index] | ~maskBytes[index]);
        }

        return new IPAddress(broadcast);
    }
}
