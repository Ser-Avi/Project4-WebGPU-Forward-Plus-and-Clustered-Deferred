// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.

@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;

@group(${bindGroup_gbuffer}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_gbuffer}) @binding(2) var<storage, read> clusterSet: ClusterSet;
@group(${bindGroup_gbuffer}) @binding(3) var albedoTex: texture_2d<f32>;
@group(${bindGroup_gbuffer}) @binding(4) var norTex: texture_2d<f32>;
@group(${bindGroup_gbuffer}) @binding(5) var posTex: texture_2d<f32>;

struct FragmentInput
{
    @builtin(position) fragPos: vec4f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f {
    // first we get all the info from the textures

    // load normals and get them back in the right space of [-1, 1] for each axis
    let normal = (textureLoad(norTex, vec2<u32>(in.fragPos.xy), 0)).xyz * 2 - 1;
    let worldPos = (textureLoad(posTex, vec2<u32>(in.fragPos.xy), 0)).xyz;
    let albedo = textureLoad(albedoTex, vec2<u32>(in.fragPos.xy), 0);

    // next, we already have our fragment pixel coords, so we skip a bunch, but
    // we pretty much follow the forward+ fs code
    let numClustersX = f32(${clusterCountX});
    let numClustersY = f32(${clusterCountY});
    let numClustersZ = f32(${clusterCountZ});

    let clusterIdxX = u32(in.fragPos.x / camera.resolution.x * numClustersX);
    let clusterIdxY = u32(in.fragPos.y / camera.resolution.y * numClustersY);
    
    // z calc
    // first we normalize
    let viewZ = (camera.viewMat * vec4f(worldPos, 1)).z;
    let normalizedDepth = log(-viewZ / f32(camera.near)) / log(f32(camera.far / camera.near));
    // then we get index with an out of bounds check just to be safe
    let clusterIdxZ = min(u32(normalizedDepth * numClustersZ), u32(numClustersZ) - 1u);

    let clusterIdx = clusterIdxX + clusterIdxY * u32(numClustersX) + clusterIdxZ * u32(numClustersX * numClustersY);

    // next, we set up the light contributions
    var totalLightContrib = vec3f(0, 0, 0);
    let clustNumLights = u32(clusterSet.clusters[clusterIdx].numLights);
    // calculate light contributions
    for (var i = 0u; i < clustNumLights; i++) {
        let lightIndex = clusterSet.clusters[clusterIdx].lightIdx[i];
        let light = lightSet.lights[lightIndex];
        totalLightContrib += calculateLightContrib(light, worldPos, normalize(normal));
    }

    var finalColor = albedo.rgb * totalLightContrib;

    return vec4f(finalColor, 1);
}