import QtQuick
import QtQuick.Shapes

// One Image decoder and a textured rounded path; no offscreen mask pass.
Item {
    id: renderer
    objectName: "nativePreviewRenderer"
    property url source: ""
    property url fallbackSource: ""
    property var sourceGeometry: [1, 1]
    property var fallbackGeometry: [1, 1]
    property size sourceSize: Qt.size(1000, 700)
    property real cornerRadius: 22
    property bool highlighted: true
    property string failedUrl: ""
    property url displayedUrl: ""
    property real displayedRatio: 1
    readonly property url imageUrl: failedUrl === source.toString() ? fallbackSource : source
    readonly property int status: photo.status
    readonly property bool prepared: status === Image.Error
        || (status === Image.Ready && displayedUrl.toString() === imageUrl.toString())
    readonly property bool frameReady: prepared
    signal traceEvent(string stage)

    Image {
        id: photo
        objectName: "nativePreviewImage"
        anchors.fill: parent
        visible: false
        source: renderer.imageUrl
        sourceSize: renderer.sourceSize
        asynchronous: true
        retainWhileLoading: true
        fillMode: Image.Stretch
        onSourceChanged: if (source.toString() !== "") renderer.traceEvent("image-load-requested")
        onStatusChanged: {
            if (status === Image.Ready) {
                const geometry = renderer.failedUrl === renderer.source.toString()
                    ? renderer.fallbackGeometry : renderer.sourceGeometry
                renderer.displayedRatio = Math.max(1, geometry[0]) / Math.max(1, geometry[1])
                renderer.displayedUrl = source
                renderer.traceEvent("image-load-completed")
            } else if (status === Image.Error && renderer.failedUrl !== renderer.source.toString()
                       && renderer.fallbackSource.toString() !== "" && source.toString() !== renderer.fallbackSource.toString()) {
                renderer.failedUrl = renderer.source.toString()
            }
        }
    }
    Shape {
        id: roundedShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: roundedPath
            readonly property real inset: renderer.highlighted ? 1 : 0.5
            readonly property real r: renderer.cornerRadius
            readonly property real right: roundedShape.width - inset
            readonly property real bottom: roundedShape.height - inset
            strokeWidth: renderer.highlighted ? 2 : 1
            strokeColor: renderer.highlighted ? "#b3ffffff" : "#54ffffff"
            fillItem: photo
            startX: inset + r
            startY: inset
            PathLine { x: roundedShape.width - roundedPath.inset - roundedPath.r; y: roundedPath.inset }
            PathQuad { x: roundedPath.right; y: roundedPath.inset + roundedPath.r; controlX: roundedPath.right; controlY: roundedPath.inset }
            PathLine { x: roundedPath.right; y: roundedPath.bottom - roundedPath.r }
            PathQuad { x: roundedPath.right - roundedPath.r; y: roundedPath.bottom; controlX: roundedPath.right; controlY: roundedPath.bottom }
            PathLine { x: roundedPath.inset + roundedPath.r; y: roundedPath.bottom }
            PathQuad { x: roundedPath.inset; y: roundedPath.bottom - roundedPath.r; controlX: roundedPath.inset; controlY: roundedPath.bottom }
            PathLine { x: roundedPath.inset; y: roundedPath.inset + roundedPath.r }
            PathQuad { x: roundedPath.inset + roundedPath.r; y: roundedPath.inset; controlX: roundedPath.inset; controlY: roundedPath.inset }
        }
    }
}
