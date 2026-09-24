import Foundation

/// A multipart upload of one WAV file plus form fields, as the engine's HTTP endpoints take it.
enum Multipart {
    static func request(_ base: URLRequest, fields: [String: String], wav: Data) -> (
        URLRequest, Data
    ) {
        let boundary = "earshot-\(UUID().uuidString)"
        var request = base
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(
                Data(
                    "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
                        .utf8))
        }
        body.append(
            Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
                    .utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return (request, body)
    }
}
