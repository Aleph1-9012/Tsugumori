pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
    id: corner
    required property int index
    required property bool compact
    required property string label
    property bool live: false
    property real span: width - 10
    readonly property color white: "#e4e2dc"
    readonly property color grey: "#aaa59b"
    readonly property color dim: "#57534b"
    readonly property color red: "#d1161c"
    readonly property bool animating: live && visible
    property real travel: 0
    property real signalOpacity: 0
    readonly property real stationSpacing: (span - 18) / 3 + 8
    readonly property int activeStation: index === 2 && animating ? Math.min(3, Math.floor((travel + .01) / stationSpacing)) : 3

    // Routes and vector paths stay fixed. Only small native rectangles move.
    readonly property var segments: {
        var points = [], result = [], distance = 0;
        if (index === 0) {
            points = [[26,5], [26,28], [10,28], [10,16], [35,16]];
        } else if (index === 1) {
            points = [[0,32], [span-56,32], [span-56,22], [span-48,22]];
        } else if (index === 2) {
            var step = (span - 18) / 3;
            points.push([9,10]);
            for (var i = 0; i < 3; i++) {
                var x = 9 + i * step, y = 10 + (i % 2 ? 8 : 0);
                var nextY = 10 + ((i + 1) % 2 ? 8 : 0);
                points.push([x + step / 2,y], [x + step / 2,nextY], [x + step,nextY]);
            }
        } else if (index === 3) {
            points = [[0,9], [0,33], [span-14,33], [span-14,43]];
        }
        for (var j = 1; j < points.length; j++) {
            var a = points[j - 1], b = points[j];
            var length = Math.abs(b[0] - a[0]) + Math.abs(b[1] - a[1]);
            result.push({x:a[0], y:a[1], dx:Math.sign(b[0] - a[0]),
                dy:Math.sign(b[1] - a[1]), start:distance, length:length});
            distance += length;
        }
        return result;
    }
    readonly property real routeLength: segments.length ? segments[segments.length - 1].start + segments[segments.length - 1].length : 0
    readonly property point signalPosition: {
        for (var i = 0; i < segments.length; i++) {
            var s = segments[i];
            if (travel <= s.start + s.length || i === segments.length - 1) {
                var offset = Math.max(0, Math.min(s.length, travel - s.start));
                return Qt.point(s.x + s.dx * offset, s.y + s.dy * offset);
            }
        }
        return Qt.point(0, 0);
    }
    SequentialAnimation {
        running: corner.animating
        loops: Animation.Infinite
        onStopped: { corner.travel = 0; corner.signalOpacity = 0; }
        PropertyAction { target: corner; property: "travel"; value: 0 }
        NumberAnimation { target: corner; property: "signalOpacity"; from: 0; to: 1; duration: 140 }
        PauseAnimation { duration: corner.index === 1 ? 700 : corner.index === 3 ? 1100 : 300 }
        NumberAnimation {
            target: corner; property: "travel"; from: 0; to: corner.routeLength
            duration: corner.index === 0 ? 2100 : corner.index === 1 ? 2800 : corner.index === 2 ? 2600 : 3100
            easing.type: Easing.Linear
        }
        PauseAnimation { duration: corner.index === 0 ? 220 : 700 }
        NumberAnimation { target: corner; property: "signalOpacity"; from: 1; to: 0; duration: 180 }
        PauseAnimation { duration: corner.index === 0 ? 650 : 900 }
    }
    function diamond(x,y) { return "M"+x+","+(y-3)+" l3,3 -3,3 -3,-3 Z"; }
    readonly property var paths: {
        var w=span, p=[];
        function add(d,color,fill,station) { p.push({d:d,color:color,fill:fill||"transparent",station:station === undefined ? -1 : station}); }
        if(index===0) {
            add("M0,35 V5 H26 V28 H10 V16 H35",grey);
            add("M6,0 V39 H21",red); add(diamond(26,5),red,red);
        } else if(index===1) {
            add("M"+(w-43)+",6 H"+w+" V38 H"+(w-43),red);
            add("M0,32 H"+(w-56)+" V22 H"+(w-48),dim); add(diamond(0,32),grey);
        } else if(index===2) {
            var step=(w-18)/3;
            for(var i=0;i<4;i++) {
                var x=9+i*step,y=10+(i%2?8:0),nextY=10+((i+1)%2?8:0);
                if(i<3)add("M"+x+","+y+" H"+(x+step*.5)+" V"+nextY+" H"+(x+step),dim);
                add(diamond(x,y),i===3?red:grey,i===3?red:"transparent",i);
            }
        } else {
            add("M0,9 V33 H"+(w-14)+" V43",grey);
            add("M"+(w-4)+",4 V25 H"+(w-29),red); add(diamond(w-14,43),red,red);
        }
        return p;
    }
    readonly property var labels: {
        var w=span, p=[];
        function add(text,x,y,color,size,weight,space,align) {
            p.push({text:text,x:x,y:y,color:color,size:size||11,weight:weight||400,space:space||0,align:align||"left"});
        }
        if(index===0) { add("TSUGUMORI",44,13,white,11,500,compact?0:.7); add("TYPE-17",44,33,grey); }
        else if(index===1) { add("704",w-22,23,red,20,500,0,"center"); add("SID0NIA",0,13,white,11,500,.3); }
        else if(index===2) for(var i=0;i<4;i++)add("0"+(i+1),9+i*(w-18)/3,38,i===3?red:grey,11,400,0,"center");
        else { add(label,w-15,12,white,11,500,.6,"right"); if(!compact)add("LOCAL // 17",8,19,grey); }
        return p;
    }
    Rectangle { anchors.fill: parent; color: "#080808" }
    Repeater {
        model: corner.paths
        Shape {
            id: shape
            required property var modelData
            readonly property bool station: modelData.station >= 0
            readonly property bool selected: modelData.station === corner.activeStation
            x: 5; y: 3
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1
                strokeColor: shape.station ? (shape.selected ? corner.red : corner.grey) : shape.modelData.color
                fillColor: shape.station ? (shape.selected ? corner.red : "transparent") : shape.modelData.fill
                capStyle: ShapePath.FlatCap; joinStyle: ShapePath.MiterJoin
                PathSvg { path: shape.modelData.d }
            }
        }
    }
    Item {
        x: 5; y: 3
        visible: corner.animating
        opacity: corner.signalOpacity
        Repeater {
            model: corner.segments
            Rectangle {
                required property var modelData
                readonly property real leading: Math.max(0, Math.min(modelData.length, corner.travel - modelData.start))
                readonly property real trailing: Math.max(0, Math.min(modelData.length, corner.travel - modelData.start - (corner.index === 0 ? 12 : 22)))
                readonly property real extent: leading - trailing
                x: modelData.x + modelData.dx * (modelData.dx < 0 ? leading : trailing) - (modelData.dx === 0 ? .5 : 0)
                y: modelData.y + modelData.dy * (modelData.dy < 0 ? leading : trailing) - (modelData.dy === 0 ? .5 : 0)
                width: modelData.dx === 0 ? 1 : extent
                height: modelData.dy === 0 ? 1 : extent
                visible: extent > 0
                color: corner.red
            }
        }
        Rectangle {
            x: corner.signalPosition.x - width / 2
            y: corner.signalPosition.y - height / 2
            width: 3; height: 3; rotation: 45
            antialiasing: true
            color: corner.red
        }
    }
    Repeater {
        model: corner.labels
        Text {
            required property int index
            required property var modelData
            x: 5 + modelData.x - (modelData.align==="right"?width:modelData.align==="center"?width/2:0)
            y: 3 + modelData.y - height/2
            text: modelData.text; textFormat: Text.PlainText
            color: corner.index === 2 ? (index === corner.activeStation ? corner.red : corner.grey) : modelData.color
            font { family: "JetBrains Mono"; pixelSize: modelData.size; weight: modelData.weight; letterSpacing: modelData.space }
            renderType: Text.CurveRendering
        }
    }
}
