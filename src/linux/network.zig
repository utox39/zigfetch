const std = @import("std");
const c = @import("c");

/// Struct representing Network informations (interface name - ipv4 address)
pub const NetInfo = struct {
    interface_name: []u8,
    ipv4_addr: []u8,
};

pub fn getNetInfo(gpa: std.mem.Allocator) !std.array_list.Managed(NetInfo) {
    var net_info_list = std.array_list.Managed(NetInfo).init(gpa);

    var ifap: ?*c.ifaddrs = null;
    if (c.getifaddrs(&ifap) != 0) {
        return error.GetifaddrsFailed;
    }
    defer c.freeifaddrs(ifap);

    var cur: ?*c.ifaddrs = ifap;
    while (cur) |ifa| : (cur = ifa.ifa_next) {
        if (ifa.ifa_addr) |addr| {
            // Skips the loopback
            if ((ifa.ifa_flags & c.IFF_LOOPBACK) != 0) continue;

            const sockaddr_ptr = @as(*const c.sockaddr, @ptrCast(@alignCast(addr)));

            if (sockaddr_ptr.sa_family != c.AF_INET) continue;

            const addr_in = @as(*const c.sockaddr_in, @ptrCast(@alignCast(sockaddr_ptr)));
            const bytes = std.mem.asBytes(&addr_in.sin_addr.s_addr);
            const ipv4_addr = try std.fmt.allocPrint(gpa, "{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] });

            try net_info_list.append(NetInfo{
                .interface_name = try gpa.dupe(u8, std.mem.span(ifa.ifa_name)),
                .ipv4_addr = ipv4_addr,
            });
        }
    }

    return net_info_list;
}
