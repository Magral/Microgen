// Ribbon culling optimization for large scenes
// Fixes missing ribbons when zooming into dense areas in v1.2

use crate::math::{Matrix4, Vector3};
use crate::scene::{Ribbon, SceneObject};

/// Frustum planes for culling calculations
#[derive(Debug, Clone)]
pub struct Frustum {
    pub left: Plane,
    pub right: Plane,
    pub top: Plane,
    pub bottom: Plane,
    pub near: Plane,
    pub far: Plane,
}

impl Frustum {
    /// Create frustum from view-projection matrix
    pub fn from_view_projection(vp_matrix: &Matrix4) -> Self {
        let m = vp_matrix;
        
        // Extract frustum planes from the combined view-projection matrix
        let left = Plane::new(
            (m[3] - m[0]).normalize(),
            m[3] + m[0],
        );
        let right = Plane::new(
            (m[3] + m[0]).normalize(),
            m[3] - m[0],
        );
        let bottom = Plane::new(
            (m[3] - m[1]).normalize(),
            m[3] + m[1],
        );
        let top = Plane::new(
            (m[3] + m[1]).normalize(),
            m[3] - m[1],
        );
        let near = Plane::new(
            (m[3] - m[2]).normalize(),
            m[3] + m[2],
        );
        let far = Plane::new(
            (m[3] + m[2]).normalize(),
            m[3] - m[2],
        );
        
        Frustum {
            left,
            right,
            top,
            bottom,
            near,
            far,
        }
    }
    
    /// Check if a point is inside the frustum
    pub fn contains_point(&self, point: &Vector3) -> bool {
        self.left.distance(point) >= 0.0 &&
        self.right.distance(point) >= 0.0 &&
        self.top.distance(point) >= 0.0 &&
        self.bottom.distance(point) >= 0.0 &&
        self.near.distance(point) >= 0.0 &&
        self.far.distance(point) >= 0.0
    }
    
    /// Check if a sphere is potentially visible (with margin for ribbon width)
    pub fn intersects_sphere_with_margin(&self, center: &Vector3, radius: f32, margin: f32) -> bool {
        let effective_radius = radius + margin;
        
        self.left.distance(center) >= -effective_radius &&
        self.right.distance(center) >= -effective_radius &&
        self.top.distance(center) >= -effective_radius &&
        self.bottom.distance(center) >= -effective_radius &&
        self.near.distance(center) >= -effective_radius &&
        self.far.distance(center) >= effective_radius
    }
}

/// A plane in 3D space for frustum culling
#[derive(Debug, Clone)]
pub struct Plane {
    pub normal: Vector3,
    pub distance: f32,
}

impl Plane {
    pub fn new(normal: Vector3, distance: f32) -> Self {
        Plane {
            normal,
            distance,
        }
    }
    
    /// Calculate signed distance from point to plane
    pub fn distance(&self, point: &Vector3) -> f32 {
        self.normal.dot(point) + self.distance
    }
}

/// Culling result for a ribbon in the scene
#[derive(Debug)]
pub struct RibbonCullResult {
    pub visible: bool,
    /// LOD level (0 = full detail, 1-3 = reduced detail)
    pub lod_level: u8,
    /// Distance from camera center
    pub distance_to_camera: f32,
}

/// Culling context for ribbon rendering
pub struct RibbonCullContext {
    pub frustum: Frustum,
    pub camera_position: Vector3,
    pub near_clip_distance: f32,
    /// Margin to account for ribbon width when culling (prevents missing ribbons)
    pub culling_margin: f32,
}

impl RibbonCullContext {
    pub fn new(view_projection_matrix: &Matrix4, camera_position: Vector3) -> Self {
        let frustum = Frustum::from_view_projection(view_projection_matrix);
        
        // Calculate appropriate margin based on typical ribbon width in the scene
        // This prevents the "missing ribbons" issue when zooming in close
        let culling_margin = 0.5; // World units, tunable per scene
        
        RibbonCullContext {
            frustum,
            camera_position,
            near_clip_distance: 0.1,
            culling_margin,
        }
    }
}

/// Cull a single ribbon and determine its LOD level
pub fn cull_ribbon(
    context: &RibbonCullContext,
    ribbon: &Ribbon,
) -> RibbonCullResult {
    let center = ribbon.get_center();
    let bounding_radius = ribbon.get_bounding_radius();
    
    // Check if ribbon is potentially visible using frustum with margin
    let visible = context.frustum.intersects_sphere_with_margin(
        &center,
        bounding_radius,
        context.culling_margin,
    );
    
    if !visible {
        return RibbonCullResult {
            visible: false,
            lod_level: 3, // Fully culled
            distance_to_camera: f32::MAX,
        };
    }
    
    // Calculate distance for LOD determination
    let distance = context.camera_position.distance(&center);
    
    // Determine LOD level based on distance and screen size
    let lod_level = determine_ribbon_lod(distance, bounding_radius);
    
    RibbonCullResult {
        visible: true,
        lod_level,
        distance_to_camera: distance,
    }
}

/// Determine appropriate LOD level for a ribbon based on distance
fn determine_ribbon_lod(distance: f32, bounding_radius: f32) -> u8 {
    // Screen-space size approximation
    let apparent_size = bounding_radius / distance;
    
    match apparent_size {
        _ if apparent_size > 0.1 => 0,   // Full detail (close-up)
        _ if apparent_size > 0.05 => 1,  // High detail
        _ if apparent_size > 0.02 => 2,  // Medium detail
        _ => 3,                           // Low detail (far away)
    }
}

/// Batch culling for multiple ribbons - optimized for large scenes
pub struct RibbonCuller {
    context: Option<RibbonCullContext>,
    results: Vec<RibbonCullResult>,
}

impl RibbonCuller {
    pub fn new() -> Self {
        RibbonCuller {
            context: None,
            results: Vec::with_capacity(1024), // Pre-allocate for typical scene sizes
        }
    }
    
    /// Begin a culling pass with the given view-projection matrix
    pub fn begin(&mut self, view_projection_matrix: &Matrix4, camera_position: Vector3) {
        self.context = Some(RibbonCullContext::new(
            view_projection_matrix,
            camera_position,
        ));
        self.results.clear();
    }
    
    /// Cull a ribbon and store the result
    pub fn cull(&mut self, ribbon: &Ribbon) -> usize {
        let context = self.context.as_ref().expect("Culler not initialized - call begin() first");
        let result = cull_ribbon(context, ribbon);
        self.results.push(result);
        self.results.len() - 1
    }
    
    /// Get the culling result for a ribbon index
    pub fn get_result(&self, index: usize) -> &RibbonCullResult {
        &self.results[index]
    }
    
    /// Check if a ribbon is visible after culling
    pub fn is_visible(&self, index: usize) -> bool {
        self.results[index].visible
    }
}

impl Default for RibbonCuller {
    fn default() -> Self {
        Self::new()
    }
}