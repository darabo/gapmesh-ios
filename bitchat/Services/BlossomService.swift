import Foundation

/// Service for uploading media files to Blossom servers (NIP-96)
/// Used as a fallback when Mesh transport is unavailable.
class BlossomService {
    static let shared = BlossomService()
    
    // Default public server
    private let defaultServerURL = URL(string: "https://cdn.satellite.earth/upload")!
    
    private init() {}
    
    enum UploadError: Error {
        case fileReadFailed
        case uploadFailed(statusCode: Int)
        case invalidResponse
        case networkError(Error)
    }
    
    /// Uploads a file to the Blossom server
    /// - Parameters:
    ///   - fileURL: The local URL of the file to upload
    ///   - mimeType: The MIME type of the file
    /// - Returns: The public URL of the uploaded file
    func uploadFile(at fileURL: URL, mimeType: String = "application/octet-stream") async throws -> URL {
        #if DEBUG
        print("[BlossomService] Starting upload for \(fileURL.lastPathComponent)")
        #endif
        
        var request = URLRequest(url: defaultServerURL)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add Authorization header if needed (NIP-98)
        
        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw UploadError.fileReadFailed
        }
        
        let body = createMultipartBody(
            data: fileData,
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            boundary: boundary
        )
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[BlossomService] Upload failed with status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("[BlossomService] Response: \(responseString)")
            }
            #endif
            throw UploadError.uploadFailed(statusCode: httpResponse.statusCode)
        }
        
        // Parse response
        // Try NIP-96 format first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let event = json["nip94_event"] as? [String: Any],
           let tags = event["tags"] as? [[String]] {
            
            // Find "url" tag
            if let urlTag = tags.first(where: { $0.first == "url" }),
               urlTag.count > 1,
               let urlString = urlTag.last,
               let url = URL(string: urlString) {
                #if DEBUG
                print("[BlossomService] Upload success (NIP-94): \(url)")
                #endif
                return url
            }
        }
        
        // Try simple JSON "url" field
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let urlString = json["url"] as? String,
           let url = URL(string: urlString) {
            #if DEBUG
            print("[BlossomService] Upload success (Simple): \(url)")
            #endif
            return url
        }
        
        throw UploadError.invalidResponse
    }
    
    private func createMultipartBody(data: Data, fileName: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}
