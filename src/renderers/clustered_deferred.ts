import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';
import { Stage } from '../stage/stage';

export class ClusteredDeferredRenderer extends renderer.Renderer {
    // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
    // you may need extra uniforms such as the camera view matrix and the canvas resolution
    sceneUniformsBindGroupLayout: GPUBindGroupLayout;
    sceneUniformsBindGroup: GPUBindGroup;

    secondBindGroupLayout: GPUBindGroupLayout;
    secondBindGroup: GPUBindGroup;

    albedoTexture: GPUTexture;
    albedoTextureView: GPUTextureView;
    normalTexture: GPUTexture;
    normalTextureView: GPUTextureView;
    positionTexture: GPUTexture;
    positionTextureView: GPUTextureView;

    depthTexture: GPUTexture;
    depthTextureView: GPUTextureView;

    firstPassPipeline: GPURenderPipeline;
    secondPassPipeline: GPURenderPipeline;

    constructor(stage: Stage) {
        super(stage);

        // TODO-3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
        // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass

        // FIRST PASS - G-buffer
        this.sceneUniformsBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "scene uniforms bind group layout",
            entries: [
                { // cam uniforms
                    binding :0,
                    visibility : GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                    buffer : { type: "uniform" }
                }]
        });

        this.sceneUniformsBindGroup = renderer.device.createBindGroup({
            label: "scene uniforms bind group",
            layout: this.sceneUniformsBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.camera.uniformsBuffer}
                }
            ]
        });

        this.albedoTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba8unorm",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.albedoTextureView = this.albedoTexture.createView();

        this.normalTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.normalTextureView = this.normalTexture.createView();

        this.positionTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.positionTextureView = this.positionTexture.createView();

        this.depthTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "depth24plus",
            usage: GPUTextureUsage.RENDER_ATTACHMENT
        });
        this.depthTextureView = this.depthTexture.createView();

        this.firstPassPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "clustered first pass pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    renderer.modelBindGroupLayout,
                    renderer.materialBindGroupLayout
                ]
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "naive vert shader",
                    code: shaders.naiveVertSrc
                }),
                buffers: [ renderer.vertexBufferLayout ]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred frag shader",
                    code: shaders.clusteredDeferredFragSrc,
                }),
                targets: [
                    // 0 - albedo
                    { format: 'rgba8unorm' },
                    // 1 - normal
                    { format: 'rgba16float' },
                    // 2 - position
                    { format: 'rgba16float' }
                ]
            }
        });


        // SECOND PASS
        this.secondBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "second pass bind group layout",
            entries: [
                { // lightSet
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }
                },
                { // clusterSet
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: {type: "read-only-storage"}
                },
                {   // albedo
                    binding: 3,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {
                        sampleType: 'float'
                    }
                },
                {   // normal
                    binding: 4,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {
                        sampleType: 'float'
                    }
                },
                {   // position
                    binding: 5,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: {
                        sampleType: 'float'
                    }
                }]
        });

        this.secondBindGroup = renderer.device.createBindGroup({
            label: "second pass bind group",
            layout: this.secondBindGroupLayout,
            entries: [
                {
                    binding: 1,
                    resource: { buffer: this.lights.lightSetStorageBuffer }
                },
                {
                    binding: 2,
                    resource: {buffer: this.lights.clusterBuffer}
                },
                {
                    binding: 3,
                    resource: this.albedoTextureView
                },
                {
                    binding: 4,
                    resource: this.normalTextureView
                },
                {
                    binding: 5,
                    resource: this.positionTextureView
                }
            ]
        });

        this.secondPassPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "clustered 2nd pass pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    renderer.modelBindGroupLayout,
                    renderer.materialBindGroupLayout,
                    this.secondBindGroupLayout
                ]
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "clustered full screen vertex shader",
                    code: shaders.clusteredDeferredFullscreenVertSrc
                }),
                buffers: [renderer.vertexBufferLayout]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "clustered full screen frag shader",
                    code: shaders.clusteredDeferredFullscreenFragSrc,
                }),
                entryPoint: "main",
                targets: [
                    {format: renderer.canvasFormat}
                ]
            }
        });
    }

    runGBufferPass()
    {
        const firstPassDescriptor: GPURenderPassDescriptor = {
            label: "cluster first pass descriptor",
            colorAttachments: [
                {
                    view: this.albedoTextureView,
                    clearValue: {r:0, g:0, b:0, a:0},
                    loadOp: "clear",
                    storeOp: "store"
                },
                {
                    view: this.normalTextureView,
                    clearValue: {r:0, g:0, b:0, a:0},
                    loadOp: "clear",
                    storeOp: "store"
                },
                {
                    view: this.positionTextureView,
                    clearValue: {r:0, g:0, b:0, a:0},
                    loadOp: "clear",
                    storeOp: "store"
                }
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
       };

       const commandEncoder = renderer.device.createCommandEncoder();
       const passEncoder = commandEncoder.beginRenderPass(firstPassDescriptor);

       passEncoder.setPipeline(this.firstPassPipeline);
       passEncoder.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);

       this.scene.iterate(
        node => {
            passEncoder.setBindGroup(shaders.constants.bindGroup_model, node.modelBindGroup);
        },
        material => {
            passEncoder.setBindGroup(shaders.constants.bindGroup_material, material.materialBindGroup);
        },
        primitive => {
            passEncoder.setVertexBuffer(0, primitive.vertexBuffer);
            passEncoder.setIndexBuffer(primitive.indexBuffer, "uint32");
            passEncoder.drawIndexed(primitive.numIndices);
        }
       );

       passEncoder.end();
       renderer.device.queue.submit([commandEncoder.finish()]);
    }

    runSecondPass() {
        const cmdEncoder = renderer.device.createCommandEncoder();
        const textureView = renderer.context.getCurrentTexture().createView();

        const renderPass = cmdEncoder.beginRenderPass({
            label: "cluster 2nd render pass",
            colorAttachments: [
                {
                    view: textureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
        });

        renderPass.setPipeline(this.secondPassPipeline);
        renderPass.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);
        renderPass.setBindGroup(shaders.constants.bindGroup_gbuffer, this.secondBindGroup);
        this.scene.iterate(
            node => {
                renderPass.setBindGroup(shaders.constants.bindGroup_model, node.modelBindGroup);
            },
            material => {
                renderPass.setBindGroup(shaders.constants.bindGroup_material, material.materialBindGroup);
            },
            primitive => {
                renderPass.setVertexBuffer(0, primitive.vertexBuffer);
                renderPass.setIndexBuffer(primitive.indexBuffer, "uint32");
                renderPass.drawIndexed(primitive.numIndices);
            }
        );

        renderPass.end();
        renderer.device.queue.submit([cmdEncoder.finish()]);
    }

    override draw() {
        // TODO-3: run the Forward+ rendering pass:
        // - run the clustering compute shader
        const computeEncoder = renderer.device.createCommandEncoder();
        this.lights.doLightClustering(computeEncoder);
        const computeCommands = computeEncoder.finish();
        renderer.device.queue.submit([computeCommands]);
        // - run the G-buffer pass, outputting position, albedo, and normals
        this.runGBufferPass();
        // - run the fullscreen pass, which reads from the G-buffer and performs lighting calculations
        this.runSecondPass();
    }
}
