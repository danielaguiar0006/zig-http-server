# Zig HTTP Server

A simple HTTP/1.1 server written in Zig. This server listens on `localhost:9090` and handles basic HTTP requests with minimal functionality:

- **GET /**: Returns a plain "OK" response.
- **GET /echo/<your string>**: Echoes back the specified string provided in the URL, along with custom headers:
  - `Content-Type: text/plain`
  - `Echo-Length: <length of echoed string>`
- **Error Handling**: Responds with appropriate HTTP status codes:
  - `404 Not Found` for undefined endpoints.
  - `405 Method Not Allowed` for unsupported request methods.
  - `400 Bad Request` and `500 Internal Server Error` for request/processing errors.

This server is intended as a learning tool for exploring Zig's networking and HTTP handling capabilities.
