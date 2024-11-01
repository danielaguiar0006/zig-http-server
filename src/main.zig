//! A simple HTTP/1.1 server in Zig.
//!
//! This program listens on port 9090 and responds with "Hello http!" to any request.
//! It also responds with "OK" to the root path ("/") and "NOT FOUND" for any other request.

const std = @import("std");

pub fn main() !void {
    const address: []const u8 = "127.0.0.1"; // Localhost
    const port: u16 = 9090;

    const endpoint = std.net.Address.parseIp4(address, port) catch |err| {
        std.debug.print("Error parsing IP address: {s}:{}\ndue to: {}\n", .{ address, port, err });
        return err;
    };

    var server = endpoint.listen(.{}) catch |err| {
        std.debug.print("Error listening on port :{}\ndue to : {}", .{ port, err });
        return err;
    };
    defer server.deinit();

    try startServer(&server);
}

/// Starts the HTTP server and accepts incoming connections.
fn startServer(server: *std.net.Server) !void {
    std.debug.print("Starting server on port {}\n", .{server.listen_address.getPort()});

    while (true) {
        var connection = server.accept() catch |err| {
            std.debug.print("Connection to client interrupted: {}\n", .{err});
            continue;
        };
        defer connection.stream.close();

        // This is how you can raw-dog write to the connection stream
        //try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");

        var read_buffer: [1024]u8 = undefined;
        var http_server = std.http.Server.init(connection, &read_buffer);

        var request = http_server.receiveHead() catch |err| {
            std.debug.print("Error receiving request: {}\n", .{err});
            continue;
        };
        handleRequest(&request) catch |err| {
            std.debug.print("Error handling request: {}\n", .{err});
            continue;
        };
    }
}

/// Handles a request and sends a response back to the client.
/// If the request is for the root path ("/"), responds with "OK" and a 200 status code.
/// Otherwise, responds with "NOT FOUND" and a 404 status code.
fn handleRequest(request: *std.http.Server.Request) !void {
    std.debug.print("Handling request for {s}\n", .{request.head.target});

    if (std.mem.eql(u8, request.head.target, "/")) {
        try request.respond("OK\n", .{ .status = .ok });
    } else {
        try request.respond("NOT FOUND\n", .{ .status = .not_found });
    }
}
