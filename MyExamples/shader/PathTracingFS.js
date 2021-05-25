import { RayIntersect } from './ShaderChunk/RayIntersect.js';

let PathTracingFS = `



//几何体的逆矩阵
uniform mat4 uShortBoxInvMatrix;
uniform mat4 uTallBoxInvMatrix;



//采样次数
uniform float uSampleCounter;
uniform float uFrameCounter;
uniform float uULen;
uniform float uVLen;

//分辨率
uniform vec2 uResolution;
uniform vec2 uRandomVec2;

//相机矩阵
uniform mat4 uCameraMatrix;

uniform sampler2D tPreviousTexture;
uniform sampler2D tBlueNoiseTexture;

#define INFINITY 1000000.

//定义平面数量
#define N_QUADS 6
#define N_SPHERES 1

//定义物体的类型
#define LIGHT 0     //光源
#define DIFF 1      //非光源，普通的对象

//定义光线
struct Ray{
    vec3 origin;
    vec3 direction;
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
    int type; //相交
};

struct RayPayload {
    vec3 radiance;
    // float t;
    vec3 scatterDirection;
    vec3 throughput;
    uint seed;
    vec3 worldHitPoint;
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
int tea(int val0, int val1) {
    int v0 = val0;
  int v1 = val1;
  int s0 = 0;

  for (int n = 0; n < 16; n++) {
    s0 += 0x9e3779b9;
    v0 += ((v1 << 4) + 0xa341316c) ^ (v1 + s0) ^ ((v1 >> 5) + 0xc8013ea4);
    v1 += ((v0 << 4) + 0xad90777d) ^ (v0 + s0) ^ ((v0 >> 5) + 0x7e95761e);
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

    //自发光颜色
    vec3 emi = vec3(0.0);

    quads[0] = Quad(
        //法线
        vec3(0.,0.,1.),
        //面的四个点
        vec3(-10.0, 10.0, -10.0),
        vec3(-10.0, -10.0, -10.0),
        vec3(10.0, -10.0, -10.0),
        vec3(10.0, 10.0, -10.0),
        //自发光颜色
        emi,
        //材质本身颜色
        vec3(1.0, 0.0, 1.0),
        //对象类型
        DIFF
    );

    //上
    quads[1] = Quad(vec3(0.,-1.,0.),
        vec3(-10.0, 10.0, -10.0),
        vec3(10.0, 10.0, -10.0),
        vec3(10.0, 10.0, 10.0),
        vec3(-10.0, 10.0,10.0),
        emi, vec3(0.7, 0.7, 0.7), DIFF
    );

    //下
    quads[2] = Quad(vec3(0.,1.,0.),
        vec3(-10.0, -10.0, -10.0),
        vec3(-10.0, -10.0, 10.0),
        vec3(10.0, -10.0, 10.0),
        vec3(10.0, -10.0,-10.0),
        emi, vec3(0.7, 0.7, 0.7), DIFF
    );

    //左
    quads[3] = Quad(vec3(1.,0.,0.),
        vec3(-10.0, 10.0, -10.0),
        vec3(-10.0, 10.0, 10.0),
        vec3(-10.0, -10.0, 10.0),
        vec3(-10.0, -10.0,-10.0),
        emi, vec3(0.0, 1.0, 0.0), DIFF
    );

    //右
    quads[4] = Quad(vec3(-1.,0.,0.),
        vec3(10.0, 10.0, -10.0),
        vec3(10.0, -10.0,-10.0),
        vec3(10.0, -10.0, 10.0),
        vec3(10.0, 10.0, 10.0),
        emi, vec3(0.0, 1.0, 0.0), DIFF
    );

    //顶部的面光源
    quads[5] = Quad(vec3(-1.,0.,0.),
        vec3(-3.0, 9.8, -3.0),
        vec3(3.0, 9.8, -3.0),
        vec3(3.0, 9.8, 3.0),
        vec3(-3.0, 9.8,3.0),
        emi, vec3(1.0, 1.0, 1.0), LIGHT
    );

    spheres[0] = Sphere (
        vec3(0.0, -5.0, 0.0),
        3.0,
        emi,
        vec3(0.7, 0.7, 0.7),
        DIFF
    );
}

//执行相交测试
${RayIntersect}

vec3 CalculateRadiance (){

    RayPayload payload;


    //相机的右方向
    vec3 camRight=vec3(uCameraMatrix[0][0],uCameraMatrix[0][1],uCameraMatrix[0][2]);
    //相机的上方向
    vec3 camUp=vec3(uCameraMatrix[1][0],uCameraMatrix[1][1],uCameraMatrix[1][2]);
    //相机的视线方向
    vec3 camForward=vec3(-uCameraMatrix[2][0],-uCameraMatrix[2][1],-uCameraMatrix[2][2]);

    seed = uvec2(uFrameCounter,uFrameCounter+1.)*uvec2(gl_FragCoord);// old way of generating random numbers

    randVec4 = texture(tBlueNoiseTexture,(gl_FragCoord.xy+(uRandomVec2*255.))/255.);// new way of rand()

    vec3 pixelColor = vec3(0.0, 0.0, 0.0);

    //每个像素采样5次
    int sampleCountPerPixel = 5;
    //该像素内每个采样点的权重
    float weightSum = 0.0;

    for(int i =0; i<sampleCountPerPixel; i++){
        vec2 pixelOffset=vec2(tentFilter(rng()),tentFilter(rng()));

        //射线的起点
        vec2 pixelPos=((gl_FragCoord.xy+pixelOffset)/uResolution)*2.-1.;
        
        //射线的方向
        vec3 rayDir=normalize(pixelPos.x*camRight*uULen+pixelPos.y*camUp*uVLen+camForward);
    
        //生成射线
        Ray ray=Ray(cameraPosition,normalize(rayDir));
    
    
        Intersection intersec;
        Quad light=quads[0];
    
        float t;

        t=RayIntersect(ray,intersec);
            
        //如果与场景中的对象均没有相交
        if(t==INFINITY){
            pixelColor += vec3(0.0, 0.0, 0.0);
        } else {
            pixelColor += intersec.color;
        }
    }

    pixelColor /= 5.0;

    return pixelColor;

}

void main(void){

    //构造场景中的mesh
    InitSceneMesh();

    //根据射线计算辐照度颜色
    vec3 pixelColor=CalculateRadiance();

    //拿到上一帧的结果
    vec3 previousColor=texelFetch(tPreviousTexture,ivec2(gl_FragCoord.xy),0).rgb;
    //如果是第一帧，则为0
    if(uFrameCounter==1.)
    {
        previousColor=vec3(0);
    }
    
    pc_fragColor=vec4(pixelColor+previousColor,1.);
}
`;

export { PathTracingFS };
