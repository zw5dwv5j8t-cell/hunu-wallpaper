import QtQuick
Canvas {
    property string symbol: ""
    property color iconColor: Theme.text
    onSymbolChanged: requestPaint()
    onIconColorChanged: requestPaint()
    onPaint: {
        const c = getContext("2d")
        c.reset(); c.clearRect(0, 0, width, height)
        c.scale(width/24, height/24)
        c.strokeStyle = iconColor; c.lineWidth = 1.7; c.lineCap = "round"; c.lineJoin = "round"
        c.beginPath()
        if (symbol === "settings") {
            c.arc(12, 12, 7, 0, Math.PI*2); c.moveTo(15, 12); c.arc(12, 12, 3, 0, Math.PI*2)
            for (let i=0; i<8; i++) { const a=i*Math.PI/4; c.moveTo(12+Math.cos(a)*7,12+Math.sin(a)*7); c.lineTo(12+Math.cos(a)*9,12+Math.sin(a)*9) }
        } else if (symbol === "image") {
            c.roundedRect(3, 4, 18, 16, 3, 3); c.moveTo(4, 17); c.lineTo(9, 12); c.lineTo(13, 16); c.lineTo(17, 12); c.lineTo(21, 16)
            c.moveTo(10, 9); c.arc(8, 9, 1.5, 0, Math.PI*2)
        } else if (symbol === "cache") {
            c.ellipse(4, 3, 16, 6); c.moveTo(4, 6); c.lineTo(4, 18); c.bezierCurveTo(4,22,20,22,20,18); c.lineTo(20,6)
            c.moveTo(4,12); c.bezierCurveTo(4,16,20,16,20,12)
        } else if (symbol === "info") {
            c.arc(12,12,9,0,Math.PI*2); c.moveTo(12,11); c.lineTo(12,17); c.moveTo(12,7); c.lineTo(12,7.2)
        } else if (symbol === "folder") {
            c.moveTo(3,7); c.lineTo(3,20); c.lineTo(21,20); c.lineTo(21,7); c.closePath()
            c.moveTo(3,7); c.lineTo(3,4); c.lineTo(10,4); c.lineTo(12,7)
        } else if (symbol === "history") {
            c.arc(12,12,8,Math.PI*1.2,Math.PI*3.05); c.moveTo(3,4); c.lineTo(3,9); c.lineTo(8,9)
            c.moveTo(12,7); c.lineTo(12,12); c.lineTo(16,14)
        } else if (symbol === "check") {
            c.moveTo(5,12); c.lineTo(10,17); c.lineTo(20,7)
        } else if (symbol === "play") {
            c.moveTo(7,4); c.lineTo(20,12); c.lineTo(7,20); c.closePath()
        } else if (symbol === "monitor") {
            c.roundedRect(2,3,20,14,2,2); c.moveTo(12,17); c.lineTo(12,21); c.moveTo(7,21); c.lineTo(17,21)
        } else if (symbol === "reset") {
            c.arc(12,12,8,Math.PI*1.2,Math.PI*3.05); c.moveTo(3,4); c.lineTo(3,9); c.lineTo(8,9)
        }
        c.stroke()
    }
}
