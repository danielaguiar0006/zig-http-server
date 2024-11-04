//! A simple HTTP/1.1 server in Zig that now supports concurrent connections through a thread pool.
//! This program echoes back the request body when there is a GET request for: "/echo/<your string>".
//! It also responds to the "/user-agent" endpoint with the recieved User-Agent header value or a "400 Bad Request" if not found.
//! Additionally, it serves files from the specified directory when there is a GET request for: "/files/<file path>".

const std = @import("std");

const CommandLineArgs = struct {
    directory: ?[]const u8,
};
var program_args: CommandLineArgs = undefined;

pub fn main() !void {
    program_args = getCommandLineArgs();

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

    startServer(&server);
}

/// Starts the server and handles incoming connections using a thread pool.
///
/// This function initializes a thread-safe allocator and a thread pool with 4 worker threads.
/// It then enters an infinite loop to accept incoming connections. Each connection is handled
/// by spawning a new task in the thread pool. If an error occurs while spawning a thread, an
/// error message is sent to the client and the connection is closed.
///
/// @param server The server instance to start and accept connections from.
fn startServer(server: *std.net.Server) void {
    std.debug.print("Starting server on port {}\n", .{server.listen_address.getPort()});

    // Ensure the use of a thread-safe allocator
    var thread_allocator: std.heap.ThreadSafeAllocator = .{ .child_allocator = std.heap.page_allocator };

    // Initialize the thread pool with 4 worker threads
    var threadpool: std.Thread.Pool = undefined;
    threadpool.init(.{ .allocator = thread_allocator.allocator(), .n_jobs = 4 }) catch unreachable;
    defer threadpool.deinit();

    while (true) {
        var connection = server.accept() catch |err| {
            std.debug.print("Connection to client interrupted: {}\n", .{err});
            continue;
        };

        threadpool.spawn(handleConnection, .{connection}) catch |err| {
            std.debug.print("Error spawning thread: {}\n", .{err});
            connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n") catch return;
            connection.stream.close();
        };
    }
}

/// Handles an incoming connection to the server.
///
/// This function reads the incoming HTTP request from the connection,
/// processes it, and sends an appropriate response back to the client.
/// If an error occurs while receiving or handling the request, it sends
/// an error response and closes the connection (If the connection is not already closed).
///
/// @param connection A pointer to the server connection to handle.
/// @return An error if the connection handling fails, otherwise void.
fn handleConnection(connection: std.net.Server.Connection) void {
    var read_buffer: [1024]u8 = undefined;
    var http_server = std.http.Server.init(connection, &read_buffer);

    var request = http_server.receiveHead() catch |err| {
        std.debug.print("Error receiving request: {}\n", .{err});

        // If I'm not able to write to the connection stream, I assume the connection is already closed and I return early
        connection.stream.writeAll("HTTP/1.1 400 Bad Request\r\n\r\n") catch return;
        connection.stream.close();
        return;
    };
    handleRequest(&request) catch |err| {
        std.debug.print("Error handling request: {}\n", .{err});
        connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n") catch return;
    };

    connection.stream.close();
}

/// Handles a request and sends a response back to the client.
pub fn handleRequest(request: *std.http.Server.Request) !void {
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
    else if (std.mem.startsWith(u8, request.head.target, "/echo/")) {
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
    else if (std.mem.startsWith(u8, request.head.target, "/user-agent")) {
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
    }
    // Respond with the contents of the specified file, its length, and a 200 status code
    // NOTE: A command-line argument is required to specify the directory containing the
    // files to be served.
    else if (std.mem.startsWith(u8, request.head.target, "/files/")) {
        if (program_args.directory == null) {
            std.debug.print("Error: No directory specified for --directory argument\n", .{});
            try request.respond("ERROR: Unable to serve files\n", .{ .status = .internal_server_error });
            return;
        } else if (request.head.target.len <= 7) {
            try request.respond("ERROR: Invalid file path\n", .{ .status = .bad_request });
            return;
        }

        // Using allocator to make sure enough memory is allocated for the file contents (which may be large)
        const allocator = std.heap.page_allocator;

        const directory = program_args.directory.?;
        const absolute_file_path = try std.fs.path.join(allocator, &[_][]const u8{ directory, request.head.target[7..] });
        defer allocator.free(absolute_file_path);

        // Open the file
        var file = std.fs.openFileAbsolute(absolute_file_path, .{}) catch |err| {
            std.debug.print("Error opening file: {s}\ndue to: {}\n", .{ absolute_file_path, err });
            try request.respond("ERROR: Unable to serve file, It may not exist!\n", .{ .status = .internal_server_error });
            return;
        };
        defer file.close();

        // Read the file contents and its length (as a string)
        const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        const file_contents_len_str = try std.fmt.allocPrint(allocator, "{d}", .{file_contents.len});
        defer allocator.free(file_contents);
        defer allocator.free(file_contents_len_str);

        // Create additional headers
        const extra_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/octet-stream" },
            .{ .name = "Content-Length", .value = file_contents_len_str },
        };

        try request.respond(file_contents, .{
            .status = .ok,
            .extra_headers = &extra_headers,
        });
    } else { // Respond with "NOT FOUND" and a 404 status code for any other request
        try request.respond("NOT FOUND\n", .{ .status = .not_found });
    }
}

/// Retrieves the command line arguments passed in to the program.
///
/// This function parses and returns the command line arguments
/// provided to the program.
///
/// @return A `CommandLineArgs` struct containing the parsed command line arguments.
fn getCommandLineArgs() CommandLineArgs {
    var build_args_iter = std.process.args();
    _ = build_args_iter.skip(); // Skip the first argument (the executable name)

    var directory: ?[]const u8 = null;

    // Iterate over the command-line arguments
    while (build_args_iter.next()) |arg| {
        // "--directory" flag where files to be served are located as an absolute path
        if (std.mem.eql(u8, arg, "--directory")) {
            directory = build_args_iter.next() orelse {
                std.debug.print("Error: No directory specified for --directory argument\n", .{});
                continue;
            };
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
        }
    }

    return .{ .directory = directory };
}
