#version 440
layout(location=0) in vec4 qt_Vertex;
layout(location=1) in vec2 qt_MultiTexCoord0;
layout(location=0) out vec4 ink;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float glyphCount;
    float pixelRatio;
    vec2 logicalSize;
    vec2 pixelOrigin;
    int glyphMode;
    int rootColumns;
    int rowIndex;
    int lineCount;
    int firstColumn;
};

float ease(float x) { x=clamp(x,0.0,1.0); return x*x*(3.0-2.0*x); }
float ramp(float p,float a,float b) { return ease((p-a)/(b-a)); }
float hash(int x,int y,int seed) {
    uint n=uint(x+1)*374761393u ^ uint(y+1)*668265263u ^ uint(seed+1)*1442695041u;
    n=(n^(n>>13u))*1274126177u;
    return float(n^(n>>16u))/4294967296.0;
}
vec2 turn(vec2 p,int angle) {
    if(angle==1) return vec2(-p.y,p.x);
    if(angle==2) return -p;
    if(angle==3) return vec2(p.y,-p.x);
    return p;
}
vec2 quadrant(int index) { return vec2(index%2==0?-1.0:1.0,index<2?-1.0:1.0); }
float fieldSplit(int key,int depth) {
    if(depth>=2 || hash(key,depth,34)<=(depth==0?.19:.58))return 0.0;
    return ramp(progress,.14+float(depth)*.15+hash(key,1,2)*.08,.55+float(depth)*.15);
}

void main() {
    // Four mesh columns per line. Both ends collapse to a point between
    // strokes, so the connecting triangles are degenerate, not extra fill.
    int column=int(round(qt_Vertex.x/logicalSize.x*float(lineCount*4-1)));
    int line=column/4, corner=column%4;
    int segments=glyphMode==1?10:9;
    int nodes=glyphMode==1?85:21;
    int root=line/(segments*nodes), node=(line/segments)%nodes, segment=line%segments;
    int depth=0;
    ivec3 route=ivec3(0);
    if(node>=21) { depth=3; int n=node-21; route=ivec3(n/16,(n%16)/4,n%4); }
    else if(node>=5) { depth=2; int n=node-5; route=ivec3(n/4,n%4,0); }
    else if(node>=1) { depth=1; route.x=node-1; }

    int key=glyphMode==1?root+1:rowIndex*rootColumns+root+firstColumn+1;
    float size=glyphMode==1?78.0:84.0, alpha=1.0, threshold=-4.0;
    vec2 center=glyphMode==1?vec2(48.0+float(root%3)*78.0,48.0+float(root/3)*78.0)
        :vec2((logicalSize.x-float(rootColumns)*84.0)*.5+(float(root+firstColumn)+.5)*84.0,42.0);
    vec2 finalCenter=center;
    float finalSize=size;
    for(int d=0;d<3;d++) {
        if(d>=depth) break;
        int child=route[d], childKey=key*5+child+1;
        float split=glyphMode==1?ease((glyphCount-threshold)/2.2):fieldSplit(key,d);
        if(glyphMode==1) {
            center+=quadrant(child)*size*.25*split;
            size*=.5;
            threshold=d==0?-2.0+hash(childKey,d,7)*25.0:threshold+6.0+hash(childKey,d,7)*16.0;
        } else {
            finalCenter+=quadrant(child)*finalSize*.25;
            finalSize*=.5;
            center=mix(center,finalCenter,split);
            size=mix(size*.72,finalSize,split);
        }
        alpha*=split;
        key=childKey;
    }
    float split=glyphMode==1?(depth<3?ease((glyphCount-threshold)/2.2):0.0):fieldSplit(key,depth);
    alpha*=1.0-split;
    if(glyphMode==0) alpha*=ramp(progress,0.0,.14);
    if(alpha<.001) {
        ink=vec4(0.0);
        gl_Position=qt_Matrix*vec4(center,0.0,1.0);
        return;
    }

    int path, part;
    if(segment<4) { path=segment/2; part=segment%2; }
    else if(segment==4) { path=2; part=0; }
    else if(segment<7) { path=3; part=segment-5; }
    else if(glyphMode==1) { path=segment==7?4:5; part=segment==7?0:segment-8; }
    else { path=4; part=segment-7; }
    vec2 a,b,c;
    bool two=true;
    float fraction=1.0;
    vec3 color;
    float lineWidth=1.0;
    if(glyphMode==1) {
        float bend=(hash(key,depth,17)-.5)*.26;
        float local=sin(glyphCount*.24+float(key))*.075;
        if(path==0){a=vec2(-.35,-.4);b=vec2(-.35,.34);c=vec2(-.14,.34);}
        else if(path==1){a=vec2(-.35,-.13);b=vec2(.31,-.13);c=vec2(.31,.12);}
        else if(path==2){a=vec2(.02+bend,-.39);b=vec2(.02+bend,.34);c=b;two=false;}
        else if(path==3){a=vec2(-.12,.12+local);b=vec2(.35,.12+local);c=vec2(.35,.39);}
        else if(path==4){a=vec2(-.4,-.39);b=vec2(-.2,-.39);c=b;two=false;}
        else {a=vec2(.22,-.4);b=vec2(.4,-.4);c=vec2(.4,-.25);}
        float tint=ease((glyphCount*.075+.23-hash(key,depth,61))/.2);
        color=mix(vec3(104,102,94),vec3(209,22,28),tint)/255.0;
        float order=hash(key,path,93);
        fraction=ramp(ramp(progress,.22,.73),order*.26,.58+order*.42);
        alpha*=fraction;
        lineWidth=max(.75,size*.031)*logicalSize.x/252.0;
    } else {
        float q=ramp(progress,.09+hash(key,depth,5)*.14,.65+float(depth)*.10);
        float shift=(1.0-q)*(hash(key,depth,6)-.5)*.34;
        if(path==0){a=vec2(-.36,-.39);b=vec2(-.36,.33);c=vec2(-.12,.33);}
        else if(path==1){a=vec2(-.36,-.12);b=vec2(.32,-.12);c=vec2(.32,.11);}
        else if(path==2){a=vec2(.02+shift,-.40);b=vec2(.02+shift,.35);c=b;two=false;}
        else if(path==3){a=vec2(-.12,.12);b=vec2(.35,.12);c=vec2(.35,.40);}
        else {a=vec2(.22,-.40);b=vec2(.40,-.40);c=vec2(.40,-.24);}
        bool red=hash(key,depth,81)>.968;
        color=(red?vec3(183,29,34):vec3(124,121,110))/255.0;
        alpha*=red?.82:.47;
        fraction=ramp(progress,.02+hash(key,path,13)*.20,.40+hash(key,path,13)*.26);
    }
    float first=length(b-a), second=two?length(c-b):0.0;
    float drawn=(first+second)*fraction;
    vec2 start=part==0?a:b, end=part==0?b:c;
    float segmentLength=part==0?first:second;
    float amount=clamp((drawn-(part==0?0.0:first))/max(segmentLength,.00001),0.0,1.0);
    end=mix(start,end,amount);
    int angle=int(floor(hash(key,depth,27)*4.0));
    start=center+turn(start*size,angle);
    end=center+turn(end*size,angle);
    if(glyphMode==1) { start*=logicalSize.x/252.0; end*=logicalSize.x/252.0; }

    float pixels=max(1.0,round(lineWidth*pixelRatio));
    float offset=mod(pixels,2.0)*.5;
    start=(round((start+pixelOrigin)*pixelRatio-vec2(offset))+vec2(offset))/pixelRatio-pixelOrigin;
    end=(round((end+pixelOrigin)*pixelRatio-vec2(offset))+vec2(offset))/pixelRatio-pixelOrigin;
    vec2 direction=end-start;
    vec2 normal=length(direction)>.00001?normalize(vec2(-direction.y,direction.x)):vec2(0.0);
    vec2 position=corner<2?start:end;
    if(corner==1 || corner==2)position+=normal*(qt_MultiTexCoord0.y-.5)*pixels/pixelRatio;
    if(alpha<.001 || amount<=0.0) { position=center; alpha=0.0; }
    ink=vec4(color*alpha,alpha)*qt_Opacity;
    gl_Position=qt_Matrix*vec4(position,0.0,1.0);
}
