// GPU-side culling pass optimization
// Reduces overdraw and improves batching for large scenes

use crate::math::{Matrix4, Vector3};
use crate::scene::SceneObject;
use std::vec::Vec;

/// Culling configuration for the render pass
#[derive(Debug, Clone)]
pub struct CullPassConfig {
    /// Enable GPU culling (vs CPU-only)
    pub enable_gpu_culling: bool,
    /// Maximum objects per batch before sorting
    pub max_batch_size: usize,
    /// LOD distance thresholds
    pub lod_distances: [f32; 4],
    /// Enable instanced rendering for identical objects
    pub enable_instancing: bool,
}

impl Default for CullPassConfig {
    fn default() -> Self {
        CullPassConfig {
            enable_gpu_culling: true,
            max_batch_size: 1024,
            lod_distances: [10.0, 50.0, 200.0, f32::MAX],
            enable_instancing: true,
        }
    }
}

/// Culling pass result - contains sorted and batched draw commands
pub struct CullPassResult {
    /// Batches of objects to render, sorted by LOD and material
    pub batches: Vec<RenderBatch>,
    /// Total visible objects after culling
    pub total_visible: usize,
}

/// A batch of objects that can be rendered together (same LOD, similar materials)
pub struct RenderBatch {
    /// Object indices in this batch
    pub object_indices: Vec<usize>,
    /// LOD level for this batch
    pub lod_level: u8,
    /// Whether to use instanced rendering
    pub is_instanced: bool,
}

/// The culling pass that prepares objects for rendering
pub struct CullPass {
    config: CullPassConfig,
    result: Option<CullPassResult>,
}

impl CullPass {
    pub fn new(config: CullPassConfig) -> Self {
        CullPass {
            config,
            result: None,
        }
    }
    
    /// Execute the culling pass for a frame
    /// Returns visible objects sorted and batched for efficient rendering
    pub fn execute(
        &mut self,
        view_projection_matrix: &Matrix4,
        camera_position: &Vector3,
        objects: &[SceneObject],
    ) -> &CullPassResult {
        let mut frustum = Frustum::from_view_projection(view_projection_matrix);
        
        // First pass: collect all visible objects with their LOD levels
        let mut visible_with_lod: Vec<(usize, u8)> = Vec::with_capacity(objects.len() / 2);
        
        for (i, obj) in objects.iter().enumerate() {
            if !obj.is_visible() || obj.is_culled_by_other_systems() {
                continue;
            }
            
            let bounds = match obj.get_bounds() {
                Some(b) => b,
                None => continue,
            };
            
            // Frustum test
            if !frustum.intersects_aabb(&bounds.min, &bounds.max) {
                continue;
            }
            
            // Determine LOD level based on distance
            let center = obj.get_center();
            let distance = camera_position.distance(&center);
            let lod_level = self.determine_lod(distance);
            
            visible_with_lod.push((i, lod_level));
        }
        
        // Sort by LOD level (far objects first for better overdraw management)
        visible_with_lod.sort_by(|a, b| {
            a.1.cmp(&b.1).then_with(|| {
                let dist_a = objects[a.0].get_center().distance(camera_position);
                let dist_b = objects[b.0].get_center().distance(camera_position);
                dist_b.partial_cmp(&dist_a).unwrap_or(std::cmp::Ordering::Equal)
            })
        });
        
        // Create render batches
        let mut batches: Vec<RenderBatch> = Vec::new();
        let mut current_batch: Option<RenderBatch> = None;
        
        for (idx, lod) in &visible_with_lod {
            let should_new_batch = match &current_batch {
                Some(batch) => {
                    batch.lod_level != *lod ||
                    batch.object_indices.len() >= self.config.max_batch_size
                }
                None => true,
            };
            
            if should_new_batch {
                if let Some(mut prev) = current_batch.take() {
                    // Check if we can use instancing
                    prev.is_instanced = self.config.enable_instancing &&
                        self.can_use_instancing(&prev.object_indices, objects);
                    batches.push(prev);
                }
                
                current_batch = Some(RenderBatch {
                    object_indices: vec![*idx],
                    lod_level: *lod,
                    is_instanced: false,
                });
            } else if let Some(ref mut batch) = current_batch {
                batch.object_indices.push(*idx);
            }
        }
        
        // Push final batch
        if let Some(mut last) = current_batch {
            last.is_instanced = self.config.enable_instancing &&
                self.can_use_instancing(&last.object_indices, objects);
            batches.push(last);
        }
        
        let total_visible = visible_with_lod.len();
        
        self.result = Some(CullPassResult {
            batches,
            total_visible,
        });
        
        &self.result.as_ref().expect("Cull pass result should be set")
    }
    
    /// Determine LOD level based on distance from camera
    fn determine_lod(&self, distance: f32) -> u8 {
        let thresholds = &self.config.lod_distances;
        
        if distance < thresholds[0] { 0 }       // Full detail
        else if distance < thresholds[1] { 1 }   // High detail
        else if distance < thresholds[2] { 2 }   // Medium detail
        else { 3 }                               // Low detail
    }
    
    /// Check if a batch can use instanced rendering (all objects must share the same mesh/material)
    fn can_use_instancing(&self, indices: &[usize], objects: &[SceneObject]) -> bool {
        if indices.len() < 4 { // Not worth instancing for small batches
            return false;
        }
        
        let first = &objects[indices[0]];
        let first_mesh_id = first.get_mesh_id();
        let first_material_id = first.get_material_id();
        
        indices.iter().all(|&idx| {
            let obj = &objects[idx];
            obj.get_mesh_id() == first_mesh_id &&
            obj.get_material_id() == first_material_id
        })
    }
}

impl Default for CullPass {
    fn default() -> Self {
        Self::new(CullPassConfig::default())
    }
}

// Frustum and Plane definitions (reused from scene_culling)
pub use crate::scene_culling::{Frustum, Plane};