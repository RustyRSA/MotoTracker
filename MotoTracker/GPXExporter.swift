import Foundation

enum GPXExporter {

    static func gpx(for ride: Ride) -> String {
        let formatter = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="MotoTracker" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Ride \(formatter.string(from: ride.startDate))</name>
            <trkseg>

        """
        for p in ride.points {
            out += "      <trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\">"
            if let ele = p.altitude {
                out += "<ele>\(String(format: "%.1f", ele))</ele>"   // schema: ele before time
            }
            out += "<time>\(formatter.string(from: p.timestamp))</time>"
            out += "<extensions><speed>\(String(format: "%.2f", p.speed))</speed></extensions>"
            out += "</trkpt>\n"
        }
        out += """
            </trkseg>
          </trk>
        </gpx>
        """
        return out
    }

    static func writeTempFile(for ride: Ride) -> URL? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        let name = "Ride_\(df.string(from: ride.startDate)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try gpx(for: ride).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
