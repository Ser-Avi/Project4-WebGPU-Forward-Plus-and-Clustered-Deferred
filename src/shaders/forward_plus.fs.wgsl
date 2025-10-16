// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).

@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f
{
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }

    // first we convert world pos to view space for easy calculations
    let viewPos = camera.viewMat * vec4f(in.pos, 1.0);
    let projPos = camera.projMat * vec4f(viewPos.xyz, 1.0);
    // next to NDC [0, 1]
    let ndc = projPos.xyz / projPos.w;
    let screenPos = ndc * 0.5 + 0.5;
    let depth = (-viewPos.z - f32(camera.near)) / f32(camera.far - camera.near);
    
    let numClustersX = f32(${clusterCountX});
    let numClustersY = f32(${clusterCountY});
    let numClustersZ = f32(${clusterCountZ});

    let clusterIdxX = u32(screenPos.x * numClustersX);
    let clusterIdxY = u32(screenPos.y * numClustersY);
    let clusterIdxZ = u32(depth * numClustersZ);

    let clusterIdx = clusterIdxX + clusterIdxY * u32(numClustersX) + clusterIdxZ * u32(numClustersX * numClustersY);

    // next, we set up the light contributions
    var totalLightContrib = vec3f(0, 0, 0);
    let clustNumLights = u32(clusterSet.clusters[clusterIdx].numLights);

    for (var i = 0u; i < clustNumLights; i++) {
        let lightIndex = clusterSet.clusters[clusterIdx].lightIdx[i];
        let light = lightSet.lights[lightIndex];
        totalLightContrib += calculateLightContrib(light, in.pos, normalize(in.nor));
    }

    var finalColor = diffuseColor.rgb * totalLightContrib;

    if (clustNumLights < 1)
    {
        finalColor = diffuseColor.rgb * vec3(1, 0, 0);
    }

    return vec4(finalColor, 1);
}