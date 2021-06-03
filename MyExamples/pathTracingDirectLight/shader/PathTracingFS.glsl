

//几何体的逆矩阵
uniform mat4 uShortBoxInvMatrix;
uniform mat4 uTallBoxInvMatrix;

//采样次数
uniform int uSampleCounter;
uniform float uFrameCounter;
uniform float uULen;
uniform float uVLen;

//分辨率
uniform vec2 uResolution;
uniform vec2 uRandomVec2;

//相机的近远裁剪面
uniform vec2 uNearFar;

//相机矩阵
uniform mat4 uCameraMatrix;

uniform mat4 uViewInverse;
uniform mat4 uProjectionInverse;

uniform sampler2D tPreviousTexture;
uniform sampler2D tBlueNoiseTexture;

#define INFINITY 1000000.
#define TWO_PI 6.28318530717958648
//定义平面数量
#define N_QUADS 6
#define N_SPHERES 1

#define uEPS_intersect.1

//定义物体的类型
#define LIGHT 0//光源
#define DIFF 1//非光源，普通的对象
#define SPEC 2

//定义光线
struct Ray{
    vec3 origin;
    vec3 direction;
    float tMin;
    float tMax;
};

struct Sphere{
    vec3 center;
    float radius;
    vec3 emission;
    vec3 color;
    int type;
};

//定义平面
struct Quad{
    //平面法线
    vec3 normal;
    
    //平面的4个点
    vec3 v0;
    vec3 v1;
    vec3 v2;
    vec3 v3;
    
    //自发光
    vec3 emission;
    //颜色
    vec3 color;
    //类型
    int type;
};

//定义相交点的信息
struct Intersection{
    vec3 normal;//相交点的法线
    vec3 emission;//自发光颜色
    vec3 color;//基础色
    int type;//相交
};

//用于保存光线追踪的结果
struct RayPayload{
    //当前计算的这一帧的像素结果
    vec3 radiance;
    // float t;
    vec3 scatterDirection;
    vec3 throughput;
    int seed;
    vec3 worldHitPoint;
    bool isRayBounceFromSpecularReflectionMaterial;
};

//用于生成随机数的种子
uvec2 seed;
vec4 randVec4=vec4(0);

float randNumber=0.;// the final randomly generated number (range: 0.0 to 1.0)
float counter=-1.;// will get incremented by 1 on each call to rand()
int channel=0;// the final selected color channel to use for rand() calc (range: 0 to 3, corresponds to R,G,B, or A)

float rand()
{
    counter++;// increment counter by 1 on every call to rand()
    // cycles through channels, if modulus is 1.0, channel will always be 0 (the R color channel)
    channel=int(mod(counter,4.));
    // but if modulus was 4.0, channel will cycle through all available channels: 0,1,2,3,0,1,2,3, and so on...
    randNumber=randVec4[channel];// get value stored in channel 0:R, 1:G, 2:B, or 3:A
    return fract(randNumber);// we're only interested in randNumber's fractional value between 0.0 (inclusive) and 1.0 (non-inclusive)
}

//这里用来生成噪声
//https://www.shadertoy.com/view/4tXyWN
float rng()
{
    seed+=uvec2(1);
    uvec2 q=1103515245U*((seed>>1U)^(seed.yx));
    uint n=1103515245U*((q.x)^(q.y>>3U));
    return float(n)*(1./float(0xffffffffU));
}

// Generate a random unsigned int from two unsigned int values, using 16 pairs
// of rounds of the Tiny Encryption Algorithm. See Zafar, Olano, and Curtis,
// "GPU Random Numbers via the Tiny Encryption Algorithm"
int tea(int val0,int val1){
    int v0=val0;
    int v1=val1;
    int s0=0;
    
    for(int n=0;n<16;n++){
        s0+=0x9e3779b9;
        v0+=((v1<<4)+0xa341316c)^(v1+s0)^((v1>>5)+0xc8013ea4);
        v1+=((v0<<4)+0xad90777d)^(v0+s0)^((v0>>5)+0x7e95761e);
    }
    
    return v0;
}

// tentFilter from Peter Shirley's 'Realistic Ray Tracing (2nd Edition)' book, pg. 60
float tentFilter(float x)
{
    return(x<.5)?sqrt(2.*x)-1.:1.-sqrt(2.-(2.*x));
}

Quad quads[N_QUADS];
Sphere spheres[N_SPHERES];

void InitSceneMesh(void){
    
    // //自发光颜色
    vec3 emi=vec3(0.);
    
    spheres[0]=Sphere(
        vec3(213.,213.,-332.),
        100.,
        emi,
        vec3(.7,.7,.7),
        DIFF
    );
    
    vec3 z=vec3(0);// No color value, Black
    vec3 L1=vec3(1.,1.,1.)*30.;// Bright Yellowish light
    
    quads[0]=Quad(
        //法线
        vec3(0.,0.,1.),
        //面的四个点
        vec3(0.,0.,-559.2),
        vec3(549.6,0.,-559.2),
        vec3(549.6,548.8,-559.2),
        vec3(0.,548.8,-559.2),
        //自发光颜色
        z,
        //材质本身颜色
        vec3(1),
        //对象类型
        DIFF
    );// Back Wall
    quads[1]=Quad(vec3(1.,0.,0.),vec3(0.,0.,0.),vec3(0.,0.,-559.2),vec3(0.,548.8,-559.2),vec3(0.,548.8,0.),z,vec3(1.,0.,0.),DIFF);// Left Wall Red
    quads[2]=Quad(vec3(-1.,0.,0.),vec3(549.6,0.,-559.2),vec3(549.6,0.,0.),vec3(549.6,548.8,0.),vec3(549.6,548.8,-559.2),z,vec3(0.,1.,0.),DIFF);// Right Wall Green
    quads[3]=Quad(vec3(0.,-1.,0.),vec3(0.,548.8,-559.2),vec3(549.6,548.8,-559.2),vec3(549.6,548.8,0.),vec3(0.,548.8,0.),z,vec3(1),DIFF);// Ceiling
    quads[4]=Quad(vec3(0.,1.,0.),vec3(0.,0.,0.),vec3(549.6,0.,0.),vec3(549.6,0.,-559.2),vec3(0.,0.,-559.2),z,vec3(1),DIFF);// Floor
    
    quads[5]=Quad(vec3(0.,-1.,0.),vec3(213.,548.,-332.),vec3(343.,548.,-332.),vec3(343.,548.,-227.),vec3(213.,548.,-227.),L1,z,LIGHT);// Area Light Rectangle in ceiling
}

//执行相交测试
// optimized algorithm for solving quadratic equations developed by Dr. Po-Shen Loh -> https://youtu.be/XKBX0r3J-9Y
// Adapted to root finding (ray t0/t1) for all quadric shapes (sphere, ellipsoid, cylinder, cone, etc.) by Erich Loftis
void solveQuadratic(float A,float B,float C,out float t0,out float t1){
    float invA=1./A;
    B*=invA;
    C*=invA;
    float neg_halfB=-B*.5;
    float u2=neg_halfB*neg_halfB-C;
    float u=u2<0.?neg_halfB=0.:sqrt(u2);
    t0=neg_halfB-u;
    t1=neg_halfB+u;
}
//-----------------------------------------------------------------------
float SphereIntersect(float rad,vec3 pos,Ray ray)
//-----------------------------------------------------------------------
{
    float t0,t1;
    vec3 L=ray.origin-pos;
    float a=dot(ray.direction,ray.direction);
    float b=2.*dot(ray.direction,L);
    float c=dot(L,L)-(rad*rad);
    solveQuadratic(a,b,c,t0,t1);
    return t0>0.?t0:t1>0.?t1:INFINITY;
}

//计算光线与三角形的相交距离，如果未相交，则返回INFINITY
float TriangleIntersect(vec3 v0,vec3 v1,vec3 v2,Ray r,bool isDoubleSided)
{
    vec3 edge1=v1-v0;
    vec3 edge2=v2-v0;
    vec3 pvec=cross(r.direction,edge2);
    float det=1./dot(edge1,pvec);
    if(!isDoubleSided&&det<0.)
    return INFINITY;
    vec3 tvec=r.origin-v0;
    float u=dot(tvec,pvec)*det;
    vec3 qvec=cross(tvec,edge1);
    float v=dot(r.direction,qvec)*det;
    float t=dot(edge2,qvec)*det;
    return(u<0.||u>1.||v<0.||u+v>1.||t<=0.)?INFINITY:t;
}

//平面求交
float QuadIntersect(vec3 v0,vec3 v1,vec3 v2,vec3 v3,Ray r,bool isDoubleSided){
    return min(TriangleIntersect(v0,v1,v2,r,isDoubleSided),TriangleIntersect(v0,v2,v3,r,isDoubleSided));
}

float RayIntersect(Ray r,inout Intersection intersect){
    vec3 normal;
    //距离
    float d;
    //默认的相交距离
    float t=INFINITY;
    bool isRayExiting=false;//光线是否停止
    
    // d=QuadIntersect(quads[0].v0,quads[0].v1,quads[0].v2,quads[0].v3,r,false);
    
    for(int i=0;i<N_QUADS;i++){
        d=QuadIntersect(quads[i].v0,quads[i].v1,quads[i].v2,quads[i].v3,r,false);
        
        //找出相交距离最短的那个，即最近的那个
        if(d<t){
            t=d;
            intersect.normal=normalize(quads[i].normal);
            intersect.emission=quads[i].emission;
            intersect.color=quads[i].color;
            intersect.type=quads[i].type;
        }
    };
    
    //与球体进行相交
    
    d=SphereIntersect(spheres[0].radius,spheres[0].center,r);
    
    if(d<t){
        t=d;
        intersect.normal=normalize((r.origin+r.direction*t)-spheres[0].center);
        intersect.emission=spheres[0].emission;
        intersect.color=spheres[0].color;
        intersect.type=spheres[0].type;
    }
    
    return t;
    
}

bool _traceRay(in Ray ray,inout RayPayload payload,in bool isCameraRay){
    
    float t;
    
    //定义相交结构体
    Intersection intersect;
    
    //场景相交测试
    t=RayIntersect(ray,intersect);
    
    return t==INFINITY;
}

void main(void){
    
    ivec2 ipos=ivec2(gl_FragCoord.xy);
    
    //每个像素采样5次
    int sampleCountPerPixel=4;
    
    //相机的右方向
    vec3 camRight=vec3(uCameraMatrix[0][0],uCameraMatrix[0][1],uCameraMatrix[0][2]);
    //相机的上方向
    vec3 camUp=vec3(uCameraMatrix[1][0],uCameraMatrix[1][1],uCameraMatrix[1][2]);
    //相机的视线方向
    vec3 camForward=vec3(-uCameraMatrix[2][0],-uCameraMatrix[2][1],-uCameraMatrix[2][2]);
    
    //构造场景中的mesh
    InitSceneMesh();
    
    RayPayload payload;
    payload.seed=tea(tea(int(gl_FragCoord.x),int(gl_FragCoord.y)),int(uSampleCounter));
    
    vec3 pixelColor=vec3(1.,0.,0.);
    //每个像素采样点的权重
    float weightSum=0.;
    
    for(int i=0;i<sampleCountPerPixel;i++){
        //在这一个像素内的偏移量
        vec2 pixelOffset=vec2(tentFilter(rng()),tentFilter(rng()));
        //射线的起点
        vec2 pixelPos=((gl_FragCoord.xy+pixelOffset)/uResolution)*2.-1.;
        
        //射线的方向
        vec3 rayDir=normalize(pixelPos.x*camRight*uULen+pixelPos.y*camUp*uVLen+camForward);
        
        vec3 wi=rayDir.xyz;
        
        //生成射线(起点，方向)
        Ray ray=Ray(cameraPosition,normalize(rayDir),uNearFar.x,uNearFar.y);
        
        //初始化颜色
        payload.radiance=vec3(0.,0.,0.);
        //渲染方程项
        payload.throughput=vec3(1.,1.,1.);
        //散射方向
        payload.scatterDirection=vec3(0.,0.,0.);
        
        //当前光线是否从相机射出(如果是则进行直接光源采样)
        bool isCameraRay=true;
        
        //当前光线是否从镜面材质的对象向射出(镜面材质的对象不进行直接光源采样)
        payload.isRayBounceFromSpecularReflectionMaterial=false;
        
        // while(true){
            bool isContinueBounce=_traceRay(
            ray,payload,isCameraRay);
        // }
        
    }
    
    //拿到上一帧的结果
    vec3 previousColor=texelFetch(tPreviousTexture,ivec2(gl_FragCoord.xy),0).rgb;
    //如果是第一帧，则为0
    if(uFrameCounter==1.)
    {
        previousColor=vec3(0);
    }
    
    pc_fragColor=vec4(pixelColor+previousColor,1.);
}
