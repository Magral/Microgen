// Main rendering module with integrated culling optimizations

use crate::math::{Matrix4, Vector3};
use crate::scene::{SceneObject, Ribbon};
use crate::ribbon_culling::{RibbonCuller, RibbonCullContext};
use crate::scene_culling::SceneCuller;
use crate::render_passes::cull_pass::{CullPass, CullPassConfig};

/// Renderer state managing all culling and rendering systems
pub struct RendererState {
    /// Scene-level spatial culling
    scene_culler: SceneCuller,
    
    /// Ribbon-specific culling (for the fixed ribbon culling issue)
    ribbon_culler: RibbonCuller,
    
    /// GPU-side culling pass for batching and LOD
    gpu_cull_pass: CullPass,
    
    /// Current frame's visible objects
    current_visible_objects: Vec<usize>,
}

impl RendererState {
    pub fn new() -> Self {
        let cull_config = CullPassConfig::default();
        
        RendererState {
            scene_culler: SceneCuller::new(),
            ribbon_culler: RibbonCuller::new(),
            gpu_cull_pass: CullPass::new(cull_config),
            current_visible_objects: Vec::with_capacity(4096),
        }
    }
    
    /// Update the spatial index (call when scene structure changes)
    pub fn update_scene_index(&mut self, objects: &[SceneObject]) {
        self.scene_culler.build_index(objects);
    }
    
    /// Begin a new frame - called before rendering starts
    /// Integrates all culling systems for optimal performance on large scenes
    pub fn begin_frame(
        &mut self,
        view_projection_matrix: &Matrix4,
        camera_position: Vector3,
        objects: &[SceneObject],
    ) {
        // Initialize scene culler
        self.scene_culler.begin_frame(view_projection_matrix, camera_position);
        
        // Initialize ribbon culling with proper margin (fixes missing ribbons issue)
        let ribbon_context = RibbonCullContext::new(
            view_projection_matrix,
            camera_position,
        );
        self.ribbon_culler.begin(view_projection_matrix, camera_position);
        
        // Execute GPU-side culling pass for batching
        let cull_result = self.gpu_cull_pass.execute(
            view_projection_matrix,
            &camera_position,
            objects,
        );
        
        // Store visible objects for this frame
        self.current_visible_objects.clear();
        for batch in &cull_result.batches {
            self.current_visible_objects.extend(batch.object_indices.iter().copied());
        }
    }
    
    /// Get the list of visible object indices for this frame
    pub fn get_visible_objects(&self) -> &[usize] {
        &self.current_visible_objects
    }
    
    /// Cull a specific ribbon (for ribbon-specific rendering)
    pub fn cull_ribbon(&mut self, ribbon: &Ribbon) -> bool {
        // The ribbon culler handles the fixed culling logic with proper margins
        let index = self.ribbon_culler.cull(ribbon);
        self.ribbon_culler.is_visible(index)
    }
}

impl Default for RendererState {
    fn default() -> Self {
        Self::new()
    }
}