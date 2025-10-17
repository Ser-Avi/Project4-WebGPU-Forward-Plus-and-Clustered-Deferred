// TODO-2: implement the light clustering compute shader

@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;
@group(${bindGroup_model}) @binding(0) var<uniform> modelMat: mat4x4f;
@group(${bindGroup_scene}) @binding(1) var<storage> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;
// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.

// ------------------------------------
// Assigning lights to clusters:
// ------------------------------------
// For each cluster:
//     - Initialize a counter for the number of lights in this cluster.

//     For each light:
//         - Check if the light intersects with the cluster’s bounding box (AABB).
//         - If it does, add the light to the cluster's light list.
//         - Stop adding lights if the maximum number of lights is reached.

//     - Store the number of lights assigned to this cluster.

// cube intersection with sphere test
// C1 is min, C2 is max, S is sphere center, R is radius
fn testSphereAABB(C1: vec3f, C2: vec3f, S: vec3f, R: f32) -> bool {
    let dist = max(vec3f(0, 0, 0), max(C1 - S, S - C2));
    let distSq = dot(dist, dist);
    return distSq < R * R;
}

@compute
@workgroup_size(${clustersWorkgroupDimX}, ${clustersWorkgroupDimY}, ${clustersWorkgroupDimZ})
fn main(@builtin(global_invocation_id) globalIdx: vec3u) {
    let numClustersX = f32(${clusterCountX});
    let numClustersY = f32(${clusterCountY});
    let numClustersZ = f32(${clusterCountZ});
    if (globalIdx.x >= u32(numClustersX) || globalIdx.y >= u32(numClustersY) || globalIdx.z >= u32(numClustersZ)) {
        return;
    };

    let clusterIdx = globalIdx.x + 
            globalIdx.y * u32(numClustersX) + 
            globalIdx.z * u32(numClustersX * numClustersY);

    let resolution = camera.resolution;
    let tileSizeX = resolution.x / numClustersX;
    let tileSizeY = resolution.y / numClustersY;

    let clusterScreenMinX = (f32(globalIdx.x) * tileSizeX);
    let clusterScreenMaxX = (f32(globalIdx.x + 1) * tileSizeX);
    let clusterScreenMinY = (f32(globalIdx.y) * tileSizeY);
    let clusterScreenMaxY = (f32(globalIdx.y + 1) * tileSizeY);

    let maxPoint_vS = screenToView(vec4f(clusterScreenMaxX, clusterScreenMaxY, -1.0, 1.0)).xyz;
    let minPoint_vS = screenToView(vec4f(clusterScreenMinX, clusterScreenMinY, -1.0, 1.0)).xyz;

    let tileNear = -f32(camera.near) * pow(f32(camera.far/camera.near), f32(globalIdx.z) / numClustersZ);
    let tileFar = -f32(camera.near) * pow(f32(camera.far/camera.near), f32(globalIdx.z + 1) / numClustersZ);

    let minPointNear = minPoint_vS * (tileNear / minPoint_vS.z);
    let minPointFar = minPoint_vS * (tileFar / minPoint_vS.z);
    let maxPointNear = maxPoint_vS * (tileNear / maxPoint_vS.z);
    let maxPointFar = maxPoint_vS * (tileFar / maxPoint_vS.z);
    
    let minPointAABB = min(min(minPointNear, minPointFar), min(maxPointNear, maxPointFar));
    let maxPointAABB = max(max(minPointNear, minPointFar), max(maxPointNear, maxPointFar));

    // initializing number of lights to 0
    clusterSet.clusters[clusterIdx].numLights = 0;

    // loop over each light
    for (var lightIdx = 0u; lightIdx < lightSet.numLights; lightIdx++) {
        let light = lightSet.lights[lightIdx];
        // NOTE: had to hardcode light rad to 2 here for github pages
        if (testSphereAABB(minPointAABB, maxPointAABB, (camera.viewMat * vec4f(light.pos, 1.0)).xyz, 2))
        {
            clusterSet.clusters[clusterIdx].lightIdx[clusterSet.clusters[clusterIdx].numLights] = lightIdx;
            clusterSet.clusters[clusterIdx].numLights++;
            if (clusterSet.clusters[clusterIdx].numLights >= ${maxLightPerCluster}) {
                break;
            }
        }
    }
}

fn screenToView(screen: vec4f) -> vec4f {
    let texCoord = (screen.xy / camera.resolution);
    let clip = vec4f(vec2f(texCoord.x, 1 - texCoord.y), screen.z, screen.w) * 2 - 1;
    var view = camera.projInvMat * clip;
    view /= view.w;
    return view;
}