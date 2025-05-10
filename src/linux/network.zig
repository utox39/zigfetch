const std = @import("std");
const c_ifaddrs = @cImport(@cInclude("ifaddrs.h"));
const c_inet = @cImport(@cInclude("arpa/inet.h"));
const c_net_if = @cImport(@cInclude("net/if.h"));
const c_netinet_in = @cImport(@cInclude("netinet/in.h"));
const c_socket = @cImport(@cInclude("sys/socket.h"));

pub const NetInfo = struct {
    interface_name: []u8,
    ipv4_addr: []u8,

    pub fn toStr(self: NetInfo, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "({s}): {s}", .{ self.interface_name, self.ipv4_addr });
    }
};

pub fn getNetInfo(allocator: std.mem.Allocator) !std.ArrayList(NetInfo) {
    var net_info_list = std.ArrayList(NetInfo).init(allocator);

    var ifap: ?*c_ifaddrs.ifaddrs = null;
    if (c_ifaddrs.getifaddrs(&ifap) != 0) {
        return error.GetifaddrsFailed;
    }
    defer c_ifaddrs.freeifaddrs(ifap);

    var cur: ?*c_ifaddrs.ifaddrs = ifap;
    while (cur) |ifa| : (cur = ifa.ifa_next) {
        if (ifa.ifa_addr) |addr| {
            // Skips the loopback
            if ((ifa.ifa_flags & c_net_if.IFF_LOOPBACK) != 0) continue;

            const sockaddr_ptr = @as(*const c_socket.sockaddr, @ptrCast(@alignCast(addr)));

            if (sockaddr_ptr.sa_family != c_inet.AF_INET) continue;

            var addr_in = @as(*const c_netinet_in.sockaddr_in, @ptrCast(@alignCast(sockaddr_ptr)));
            var ip_buf: [c_inet.INET_ADDRSTRLEN]u8 = undefined;
            const ip_str = c_inet.inet_ntop(c_inet.AF_INET, &addr_in.sin_addr, &ip_buf, c_inet.INET_ADDRSTRLEN);
            if (ip_str) |ip| {
                try net_info_list.append(NetInfo{
                    .interface_name = try allocator.dupe(u8, std.mem.span(ifa.ifa_name)),
                    .ipv4_addr = try allocator.dupe(u8, std.mem.span(ip)),
                });
            }
        }
    }

    return net_info_list;
}
