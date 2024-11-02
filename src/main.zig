//! A simple HTTP/1.1 server in Zig.
//! This program echoes back the request body when there is a GET request for: "/echo/<your string>".
//! It also responds to the "/user-agent" endpoint with the recieved User-Agent header value or a "400 Bad Request" if not found.

const std = @import("std");

pub fn main() !void {
    const address: []const u8 = "127.0.0.1"; // Localhost
    const port: u16 = 9090;

    const endpoint = std.net.Address.parseIp4(address, port) catch |err| {
        std.debug.print("Error parsing IP address: {s}:{}\ndue to: {}\n", .{ address, port, err });
        return err;
    };

    var server = endpoint.listen(.{ .reuse_address = true }) catch |err| {
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
            try connection.stream.writeAll("HTTP/1.1 400 Bad Request\r\n\r\n");
            connection.stream.close();
            continue;
        };
        handleRequest(&request) catch |err| {
            std.debug.print("Error handling request: {}\n", .{err});
            try connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n");
            connection.stream.close();
            continue;
        };
    }
}

/// Handles a request and sends a response back to the client.
fn handleRequest(request: *std.http.Server.Request) !void {
    std.debug.print("Handling request for {s}\n", .{request.head.target});

    // Respond with "NOT GET" and a 404 status code when the request is not a GET request
    if (request.head.method != .GET) {
        try request.respond("METHOD NOT ALLOWED\n", .{ .status = .method_not_allowed });
        return;
    }

    // Respond with "OK" and a 200 status code when the request is for the root path ("/")
    if (std.mem.eql(u8, request.head.target, "/")) {
        try request.respond("OK\n", .{ .status = .ok });
    }
    // Echo back the request body, with a 200 status code and two response headers
    else if (request.head.target.len > 6 and std.mem.eql(u8, request.head.target[0..6], "/echo/")) {
        // Get the what was received in the request body
        const echo = request.head.target[6..];
        var echo_len_buffer: [16]u8 = undefined;
        const echo_len_str = try std.fmt.bufPrint(&echo_len_buffer, "{d}", .{echo.len});

        // Create additional headers
        const extra_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "text/plain" },

            // NOTE: Zig's std.http.Server.Request.respond function automatically adds a content-length header
            // So this is redundant, but I'm leaving it here for demonstration purposes
            .{ .name = "Echo-Length", .value = echo_len_str },
        };

        try request.respond(echo, .{
            .status = .ok,
            .extra_headers = &extra_headers,
        });
    }
    // Respond with the "User-Agent" header value or a "400 Bad Request" if not found
    else if (request.head.target.len == 11 and std.mem.eql(u8, request.head.target[0..11], "/user-agent")) {
        var user_agent_header: ?std.http.Header = null;

        // Iterate over the request headers to find the "User-Agent" header
        var request_headers_iter = request.iterateHeaders();
        while (request_headers_iter.next()) |header| {
            if (std.mem.eql(u8, header.name, "User-Agent")) {
                user_agent_header = header;
                break;
            }
        }

        // Respond with a "400 Bad Request" if the "User-Agent" header is not found
        if (user_agent_header == null) {
            try request.respond("No User-Agent header provided\n", .{ .status = .bad_request });
            return;
        }

        // Get the value and length of the "User-Agent" header
        const user_agent = user_agent_header.?.value;
        var user_agent_len_buffer: [16]u8 = undefined;
        const user_agent_len_str = try std.fmt.bufPrint(&user_agent_len_buffer, "{d}", .{user_agent.len});

        // Create additional headers
        const extra_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "text/plain" },

            // NOTE: Zig's std.http.Server.Request.respond function automatically adds a content-length header
            // So this is redundant, but I'm leaving it here for demonstration purposes
            .{ .name = "Content-Length", .value = user_agent_len_str },
        };

        try request.respond(user_agent, .{
            .status = .ok,
            .extra_headers = &extra_headers,
        });
    } else { // Respond with "NOT FOUND" and a 404 status code for any other request
        try request.respond("NOT FOUND\n", .{ .status = .not_found });
    }
}
