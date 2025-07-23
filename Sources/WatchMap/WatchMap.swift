import Foundation
import SwiftUI

public func tileXY(for coordinate: CLLocationCoordinate2D, zoom: Int) -> (x: Double, y: Double) {
    let latRad = coordinate.latitude * Double.pi / 180
    let n = pow(2.0, Double(zoom))
    let x = (coordinate.longitude + 180.0) / 360.0 * n
    let y = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / Double.pi) / 2.0 * n
    return (x, y)
}

public func coordinate(forX x: Double, y: Double, zoom: Int) -> CLLocationCoordinate2D {
    let n = pow(2.0, Double(zoom))
    let lon = x / n * 360.0 - 180.0
    let latRad = atan(sinh(Double.pi * (1 - 2 * y / n)))
    let lat = latRad * 180.0 / Double.pi
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
}

public func osmTile(z: Int, x: Int, y: Int, tileSize: Double) -> some View {
    AsyncImage(url: URL(string: "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png")) { image in
        image.resizable()
    } placeholder: {
        ProgressView()
    }
    .frame(width: tileSize, height: tileSize)
}

public func userLocationMarker(heading: Double?) -> some View {
    Circle()
        .fill(.blue)
        .frame(width: 18, height: 18)
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .background(
            heading == nil
                ? nil
                : Path { path in
                    path.move(to: .zero)
                    path.addArc(
                        center: .zero,
                        radius: 40,
                        startAngle: .degrees(-105),
                        endAngle: .degrees(-75),
                        clockwise: false)

                    path.closeSubpath()
                }
                .offset(x: 9, y: 9)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            .blue,
                            .blue.opacity(0),
                        ]),
                        center: .center,
                        startRadius: 1,
                        endRadius: 36
                    )
                )
        )
        .rotationEffect(.degrees(heading ?? 0))
}

public struct MapView<TileContent: View, UserLocationContent: View>: View {
    @Binding private var zoom: Double
    @Binding private var center: CLLocationCoordinate2D
    @Binding private var userLocation: CLLocationCoordinate2D?
    @Binding private var heading: Double?
    private let minZoom: Double
    private let maxZoom: Double
    private let tileSize: Double
    private let gridSize: Int
    private var onPan: ((CLLocationCoordinate2D) -> Void)?
    private var onTap: ((CLLocationCoordinate2D) -> Void)?
    private let tileContent: (Int, Int, Int, Double) -> TileContent
    private let userLocationContent: (Double?) -> UserLocationContent
    private let halfSpan: Double
    private let range: [Double]
    private let tapDistance: CGFloat

    @GestureState private var dragOffset: CGSize = .zero

    public init(
        zoom: Binding<Double>,
        center: Binding<CLLocationCoordinate2D>,
        userLocation: Binding<CLLocationCoordinate2D?> = .constant(nil),
        heading: Binding<Double?> = .constant(nil),
        minZoom: Double = 1,
        maxZoom: Double = 20,
        tileSize: Double = 256,
        gridSize: Int = 2,
        onPan: ((CLLocationCoordinate2D) -> Void)? = nil,
        onTap: ((CLLocationCoordinate2D) -> Void)? = nil,
        tapDistance: CGFloat = 5,
        @ViewBuilder tileContent: @escaping (Int, Int, Int, Double) -> TileContent = osmTile,
        @ViewBuilder userLocationContent: @escaping (Double?) -> UserLocationContent =
            userLocationMarker
    ) {
        self._zoom = zoom
        self._center = center
        self._userLocation = userLocation
        self._heading = heading
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.tileSize = tileSize
        self.gridSize = gridSize
        self.onPan = onPan
        self.onTap = onTap
        self.tapDistance = tapDistance
        self.tileContent = tileContent
        self.userLocationContent = userLocationContent
        halfSpan = (Double(gridSize) - 1) / 2.0
        range = Array(stride(from: -halfSpan, through: halfSpan, by: 1.0))
    }

    public var body: some View {
        let zoomInt = Int(floor(zoom))
        let zoomFraction = zoom.truncatingRemainder(dividingBy: 1)
        let scale = pow(2.0, zoomFraction)

        let dragX = dragOffset.width / scale
        let dragY = dragOffset.height / scale

        let (centerX, centerY) = tileXY(for: center, zoom: zoomInt)

        let fracX = centerX.truncatingRemainder(dividingBy: 1)
        let fracY = centerY.truncatingRemainder(dividingBy: 1)

        let shiftX = gridSize % 2 == 1 ? fracX - 0.5 : fracX > 0.5 ? 1 - fracX : -fracX
        let shiftY = gridSize % 2 == 1 ? fracY - 0.5 : fracY > 0.5 ? 1 - fracY : -fracY

        let offsetX = shiftX * tileSize
        let offsetY = shiftY * tileSize

        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .opacity(0)
                    .background(
                        ZStack {
                            VStack(spacing: 0) {
                                ForEach(range, id: \.self) { dy in
                                    HStack(spacing: 0) {
                                        ForEach(range, id: \.self) { dx in
                                            let x = Int(floor(centerX + dx))
                                            let y = Int(floor(centerY + dy))
                                            tileContent(zoomInt, x, y, tileSize)
                                        }
                                    }
                                }
                            }
                            .offset(x: offsetX, y: offsetY)
                            
                            if let userLocation = userLocation {
                                let (userX, userY) = tileXY(for: userLocation, zoom: zoomInt)
                                userLocationContent(heading)
                                    .scaleEffect(1 / scale)
                                    .offset(
                                        x: (userX - centerX) * tileSize,
                                        y: (userY - centerY) * tileSize
                                    )
                            }
                        }
                            .offset(x: dragX, y: dragY)
                            .scaleEffect(scale, anchor: .center)
                    )
                    .frame(width: tileSize * Double(gridSize), height: tileSize * Double(gridSize))
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                let isTap = abs(value.translation.width) < tapDistance && abs(value.translation.height) < tapDistance
                                if isTap, let onTap = onTap {
                                    let tapLocation = value.location
                                    let mapWidth = tileSize * Double(gridSize)
                                    let mapHeight = tileSize * Double(gridSize)
                                    let dx = (tapLocation.x - mapWidth / 2) / scale
                                    let dy = (tapLocation.y - mapHeight / 2) / scale
                                    let tileDx = dx / tileSize
                                    let tileDy = dy / tileSize
                                    let tapTileX = centerX + tileDx
                                    let tapTileY = centerY + tileDy
                                    let coord = coordinate(forX: tapTileX, y: tapTileY, zoom: zoomInt)
                                    onTap(coord)
                                } else {
                                    let scale = pow(2.0, zoom - floor(zoom))
                                    let deltaX = value.translation.width / (tileSize * scale)
                                    let deltaY = value.translation.height / (tileSize * scale)
                                    let newCenterX = centerX - deltaX
                                    let newCenterY = centerY - deltaY
                                    let newCenter = coordinate(
                                        forX: newCenterX, y: newCenterY, zoom: zoomInt)
                                    self.center = newCenter
                                    onPan?(newCenter)
                                }
                            }
                    )
#if os(watchOS)
                    .focusable()
                    .digitalCrownRotation(
                        $zoom, from: minZoom, through: maxZoom, by: 0.1, sensitivity: .medium,
                        isContinuous: false, isHapticFeedbackEnabled: true)
#endif
            }
            .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
        }.ignoresSafeArea()
    }
}

let oslo = CLLocationCoordinate2D(latitude: 59.9111, longitude: 10.7528)

#Preview {
    struct Preview: View {
        @State private var zoom: Double = 12
        @State private var center: CLLocationCoordinate2D = oslo
        @State private var userLocation: CLLocationCoordinate2D? = oslo
        @State private var heading: Double? = 125
        var body: some View {
            MapView(
                zoom: $zoom,
                center: $center,
                userLocation: $userLocation,
                heading: $heading,
                minZoom: 1,
                maxZoom: 18
            )
        }
    }
    return Preview()
}

#Preview("with userLocation") {
    struct Preview: View {
        @State private var zoom: Double = 6
        @State private var center: CLLocationCoordinate2D = oslo
        @State private var userLocation: CLLocationCoordinate2D? = oslo
        var body: some View {
            MapView(
                zoom: $zoom,
                center: $center,
                userLocation: $userLocation
            )
        }
    }
    return Preview()
}

#Preview("with gridSize=3") {
    struct Preview: View {
        @State private var zoom: Double = 10
        @State private var center: CLLocationCoordinate2D = oslo
        @State private var userLocation: CLLocationCoordinate2D? = oslo
        var body: some View {
            MapView(
                zoom: $zoom,
                center: $center,
                userLocation: $userLocation,
                tileSize: 64,
                gridSize: 3
            )
        }
    }
    return Preview()
}

#Preview("with custom marker") {
    struct Preview: View {
        @State private var zoom: Double = 16
        @State private var center: CLLocationCoordinate2D = oslo
        @State private var userLocation: CLLocationCoordinate2D? = oslo
        @State private var heading: Double? = 125
        var body: some View {
            MapView(
                zoom: $zoom,
                center: $center,
                userLocation: $userLocation,
                heading: $heading,
                userLocationContent: { heading in
                    if heading == nil {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.title3)
                            .padding(5)
                            .foregroundColor(.red)
                            .rotationEffect(.degrees(heading ?? 0))
                    }
                }
            )
        }
    }
    return Preview()
}

#Preview("with debug tiles") {
    struct Preview: View {
        @State private var zoom: Double = 6
        @State private var center: CLLocationCoordinate2D = oslo
        @State private var userLocation: CLLocationCoordinate2D? = oslo
        var body: some View {
            MapView(
                zoom: $zoom,
                center: $center,
                userLocation: $userLocation,
                tileSize: 64,
                tileContent: { z, x, y, tileSize in
                    osmTile(z: z, x: x, y: y, tileSize: tileSize)
                        .border(.red)
                        .overlay(
                            VStack {
                                Text("z:\(z)")
                                Text("x:\(x)")
                                Text("y:\(y)")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(2)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(4)
                            .padding(2)
                        )
                }
            )
        }
    }
    return Preview()
}

#Preview("with location button") {
    struct Preview: View {
        @State private var zoom: Double = 3
        @State private var center: CLLocationCoordinate2D = oslo
        @State private var userLocation: CLLocationCoordinate2D? = oslo
        var body: some View {
            ZStack {
                MapView(
                    zoom: $zoom,
                    center: $center,
                    userLocation: $userLocation
                )
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            print("Location button pressed")
                            self.center = oslo
                        }) {
                            Image(systemName: "location.fill")
                                .font(.title3)
                                .padding(5)
                                .background(.white.opacity(0.8))
                                .foregroundColor(.red)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Location button")
                        .fixedSize(horizontal: true, vertical: true)
                        Spacer()
                    }
                }.padding(.horizontal, 10)
            }
        }
    }
    return Preview()
}

#Preview("with tap callback") {
    struct Preview: View {
        @State private var alert: Bool = false
        @State private var tappedCoordinate: CLLocationCoordinate2D? = nil
        @State private var zoom: Double = 6
        @State private var center: CLLocationCoordinate2D = oslo
        var body: some View {
            MapView(
                zoom: $zoom,
                center: $center,
                onTap: { coord in
                    tappedCoordinate = coord
                    alert = true
                }
            )
            .alert(isPresented: $alert) {
                Alert(
                    title: Text("Tapped Location"),
                    message: Text(tappedCoordinate.map { String(format: "Lat: %.5f\nLon: %.5f", $0.latitude, $0.longitude) } ?? "Unknown"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    return Preview()
}

#Preview("with persistence") {
    struct Preview: View {
        @AppStorage("preview_zoom") private var zoom: Double = 12
        @AppStorage("preview_center_latitude") private var centerLatitude: Double = oslo.latitude
        @AppStorage("preview_center_longitude") private var centerLongitude: Double = oslo.longitude

        var centerBinding: Binding<CLLocationCoordinate2D> {
            Binding(
                get: { CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude) },
                set: {
                    centerLatitude = $0.latitude
                    centerLongitude = $0.longitude
                }
            )
        }

        var body: some View {
            MapView(
                zoom: $zoom,
                center: centerBinding,
            )
        }
    }
    return Preview()
}
