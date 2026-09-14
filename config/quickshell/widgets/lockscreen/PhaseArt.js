.pragma library

// The approved Phase field and K compound glyph, drawn in logical pixels.
// The window supplies DPR; snap stroke centers without scaling a cached bitmap.
function clamp(v, a = 0, b = 1) { return Math.max(a, Math.min(b, v)); }
function lerp(a, b, t) { return a + (b - a) * t; }
function smooth(v) { var x = clamp(v); return x * x * (3 - 2 * x); }
function ramp(p, a, b) { return smooth((p - a) / (b - a)); }
function hash(x, y, seed = 0) {
    var n = Math.imul(x + 1, 374761393) ^ Math.imul(y + 1, 668265263) ^ Math.imul(seed + 1, 1442695041);
    n = Math.imul(n ^ (n >>> 13), 1274126177);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

function stroke(c, points, color, width = 1, alpha = 1, fraction = 1, dpr = 1) {
    if (points.length < 2 || alpha <= .001 || fraction <= .001) return;
    var path = [points[0]], lengths = [], total = 0;
    for (var i = 1; i < points.length; i++) {
        var dx = points[i][0] - points[i-1][0], dy = points[i][1] - points[i-1][1];
        var distance = Math.sqrt(dx * dx + dy * dy);
        lengths.push(distance); total += distance;
    }
    var remaining = total * clamp(fraction);
    for (var j = 1; j < points.length; j++) {
        var length = lengths[j-1];
        if (remaining >= length) { path.push(points[j]); remaining -= length; }
        else {
            var q = length ? remaining / length : 0;
            path.push([lerp(points[j-1][0], points[j][0], q), lerp(points[j-1][1], points[j][1], q)]);
            break;
        }
    }
    var pixels = Math.max(1, Math.round(width * dpr)), offset = pixels % 2 / 2;
    function snap(v) { return (Math.round(v * dpr - offset) + offset) / dpr; }
    c.beginPath(); c.moveTo(snap(path[0][0]), snap(path[0][1]));
    for (var k = 1; k < path.length; k++) c.lineTo(snap(path[k][0]), snap(path[k][1]));
    c.lineWidth = pixels / dpr; c.strokeStyle = color; c.globalAlpha = clamp(alpha);
    c.stroke();
}

function prepare(c, w, h) {
    c.reset(); c.clearRect(0, 0, w, h);
    c.lineCap = 'butt'; c.lineJoin = 'miter';
}

function buildField(w, h) {
    var size = 84, cols = Math.ceil(w / size), rows = Math.ceil(h / size);
    var ox = (w - cols * size) / 2, oy = (h - rows * size) / 2, cells = [];
    function cell(x, y, side, key, depth) {
        var node = {x:x, y:y, size:side, key:key, depth:depth,
            angle:Math.floor(hash(key, depth, 27) * 4) * Math.PI / 2, children:[]};
        if (depth < 2 && hash(key, depth, 34) > (depth === 0 ? .19 : .58))
            for (var i = 0; i < 4; i++)
                node.children.push(cell(x + (i % 2 ? 1 : -1) * side / 4,
                    y + (i < 2 ? -1 : 1) * side / 4, side / 2, key * 5 + i + 1, depth + 1));
        return node;
    }
    for (var y = 0; y < rows; y++) for (var x = 0; x < cols; x++)
        cells.push(cell(ox + (x + .5) * size, oy + (y + .5) * size, size, y * cols + x + 1, 0));
    return cells;
}

function drawField(c, cells, p, dpr) {
    var alive = ramp(p, 0, .14);
    function glyph(node, cx, cy, size, alpha) {
        if (alpha < .006) return;
        var key = node.key, depth = node.depth;
        var q = ramp(p, .09 + hash(key, depth, 5) * .14, .65 + depth * .10);
        var shift = (1 - q) * (hash(key, depth, 6) - .5) * .34;
        var shape = [[[-.36,-.39],[-.36,.33],[-.12,.33]],
            [[-.36,-.12],[.32,-.12],[.32,.11]], [[.02+shift,-.40],[.02+shift,.35]],
            [[-.12,.12],[.35,.12],[.35,.40]], [[.22,-.40],[.40,-.40],[.40,-.24]]];
        var cos = Math.cos(node.angle), sin = Math.sin(node.angle), red = hash(key, depth, 81) > .968;
        for (var i = 0; i < shape.length; i++) {
            var local = ramp(p, .02 + hash(key, i, 13) * .20, .40 + hash(key, i, 13) * .26);
            var points = shape[i].map(function(pt) { return [cx + (pt[0]*cos - pt[1]*sin)*size, cy + (pt[0]*sin + pt[1]*cos)*size]; });
            stroke(c, points, red ? '#b71d22' : '#7c796e', 1, alpha * (red ? .82 : .47), local, dpr);
        }
    }
    function branch(node, alpha, x, y, size) {
        var split = node.children.length ? ramp(p, .14 + node.depth*.15 + hash(node.key,1,2)*.08, .55 + node.depth*.15) : 0;
        glyph(node, x, y, size, alpha * (1 - split) * alive);
        if (split > 0) for (var i = 0; i < node.children.length; i++) {
            var child = node.children[i];
            branch(child, alpha*split, lerp(x,child.x,split), lerp(y,child.y,split), lerp(size*.72,child.size,split));
        }
    }
    for (var i = 0; i < cells.length; i++) {
        var node = cells[i]; branch(node, 1, node.x, node.y, node.size);
    }
    c.globalAlpha = 1;
}

function componentState(p) {
    return {back:ramp(p,.10,.35), border:ramp(p,.18,.73), folio:ramp(p,.28,.67),
        folioText:ramp(p,.49,.76), user:ramp(p,.41,.68), clock:ramp(p,.48,.74),
        glyph:ramp(p,.22,.73), auth:ramp(p,.59,.87)};
}

function glyphMarks(p) {
    var marks = [];
    function glyph(cx, cy, size, key, depth, alpha) {
        if (alpha < .004) return;
        var a = Math.floor(hash(key,depth,27)*4)*Math.PI/2, cos = Math.cos(a), sin = Math.sin(a);
        var bend = (hash(key,depth,17)-.5)*.26, local = Math.sin(p*.24+key)*.075;
        var shape = [[[-.35,-.4],[-.35,.34],[-.14,.34]], [[-.35,-.13],[.31,-.13],[.31,.12]],
            [[.02+bend,-.39],[.02+bend,.34]], [[-.12,.12+local],[.35,.12+local],[.35,.39]],
            [[-.4,-.39],[-.2,-.39]], [[.22,-.4],[.4,-.4],[.4,-.25]]];
        // Increased red coverage only. Keep the approved K geometry and timing.
        var tint = smooth((p*.075+.23-hash(key,depth,61))/.2);
        var color = 'rgb('+Math.round(lerp(104,209,tint))+','+Math.round(lerp(102,22,tint))+','+Math.round(lerp(94,28,tint))+')';
        for (var i = 0; i < shape.length; i++) {
            var points = shape[i].map(function(pt) { return [cx+(pt[0]*cos-pt[1]*sin)*size, cy+(pt[0]*sin+pt[1]*cos)*size]; });
            marks.push({points:points,c:color,w:Math.max(.75,size*.031),alpha:alpha});
        }
    }
    function branch(cx,cy,size,key,depth,threshold,alpha) {
        var split = depth < 3 ? smooth((p-threshold)/2.2) : 0;
        glyph(cx,cy,size,key,depth,alpha*(1-split));
        if (split > 0) for (var child = 0; child < 4; child++) {
            var childKey = key*5+child+1;
            var next = depth===0 ? -2+hash(childKey,depth,7)*25 : threshold+6+hash(childKey,depth,7)*16;
            branch(cx+(child%2?1:-1)*size*.25*split, cy+(child<2?-1:1)*size*.25*split,
                size*.5,childKey,depth+1,next,alpha*split);
        }
    }
    for (var y = 0; y < 3; y++) for (var x = 0; x < 3; x++) branch(48+x*78,48+y*78,78,y*3+x+1,0,-4,1);
    return marks;
}

function drawGlyph(c, side, p, progress, dpr) {
    var marks = glyphMarks(p), scale = side/252, q = componentState(progress).glyph;
    for (var i = 0; i < marks.length; i++) {
        var mark = marks[i], local = ramp(q,hash(i,0,93)*.26,.58+hash(i,0,93)*.42);
        var points = mark.points.map(function(pt) { return [pt[0]*scale,pt[1]*scale]; });
        stroke(c,points,mark.c,mark.w*scale,mark.alpha*local,local,dpr);
    }
    c.globalAlpha = 1;
}
