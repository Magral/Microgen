// Scene-level spatial culling optimization
// Addresses performance issues with 50k+ object scenes

use crate::math::{Matrix4, Vector3};
use crate::scene::SceneObject;
use std::collections::HashMap;

/// Spatial partitioning structure for efficient large scene culling
pub struct SceneCuller {
    /// Octree-based spatial index for fast visibility queries
    octree: Option<Octree>,
    /// Frustum for current frame
    frustum: Option<Frustum>,
    camera_position: Vector3,
    
    // LOD configuration
    lod_distances: [f32; 4], // Distance thresholds for each LOD level
    
    // Results storage
    visible_objects: Vec<usize>,
}

impl SceneCuller {
    pub fn new() -> Self {
        SceneCuller {
            octree: None,
            frustum: None,
            camera_position: Vector3::ZERO,
            lod_distances: [10.0, 50.0, 200.0, f32::MAX],
            visible_objects: Vec::with_capacity(4096), // Pre-allocate for large scenes
        }
    }
    
    /// Build spatial index from scene objects (call once when scene changes)
    pub fn build_index(&mut self, objects: &[SceneObject]) {
        let mut tree = Octree::new();
        
        // Insert all objects into the octree
        for (i, obj) in objects.iter().enumerate() {
            if let Some(bounds) = obj.get_bounds() {
                tree.insert(i, bounds);
            }
        }
        
        self.octree = Some(tree);
    }
    
    /// Begin a culling pass for the current frame
    pub fn begin_frame(&mut self, view_projection_matrix: &Matrix4, camera_position: Vector3) {
        self.frustum = Some(Frustum::from_view_projection(view_projection_matrix));
        self.camera_position = camera_position;
        self.visible_objects.clear();
    }
    
    /// Perform culling and return visible object indices
    pub fn cull_scene(&mut self, objects: &[SceneObject]) -> &Vec<usize> {
        let frustum = self.frustum.as_ref().expect("Not initialized - call begin_frame() first");
        
        // Use octree for spatial queries if available (much faster for large scenes)
        if let Some(ref tree) = self.octree {
            tree.query_frustum(frustum, &self.camera_position, |idx| {
                // Additional per-object checks
                let obj = &objects[idx];
                
                // Check LOD and visibility flags
                if obj.is_visible() && !obj.is_culled_by_other_systems() {
                    self.visible_objects.push(idx);
                }
            });
        } else {
            // Fallback: brute force (for small scenes or when index not built)
            for (i, obj) in objects.iter().enumerate() {
                if let Some(bounds) = obj.get_bounds() {
                    if frustum.intersects_aabb(&bounds.min, &bounds.max) && 
                       obj.is_visible() &&
                       !obj.is_culled_by_other_systems() {
                        self.visible_objects.push(i);
                    }
                }
            }
        }
        
        // Sort by distance for better LOD batching
        self.visible_objects.sort_by(|&a, &b| {
            let dist_a = objects[a].get_center().distance(&self.camera_position);
            let dist_b = objects[b].get_center().distance(&self.camera_position);
            dist_a.partial_cmp(&dist_b).unwrap_or(std::cmp::Ordering::Equal)
        });
        
        &self.visible_objects
    }
}

impl Default for SceneCuller {
    fn default() -> Self {
        Self::new()
    }
}

/// Frustum representation (same as ribbon_culling but kept separate for module independence)
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
    pub fn from_view_projection(vp_matrix: &Matrix4) -> Self {
        let m = vp_matrix;
        
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
    
    /// Check if an AABB intersects the frustum
    pub fn intersects_aabb(&self, min: &Vector3, max: &Vector3) -> bool {
        // Test each corner of the AABB against all planes
        let corners = [
            Vector3::new(min.x, min.y, min.z),
            Vector3::new(max.x, min.y, min.z),
            Vector3::new(min.x, max.y, min.z),
            Vector3::new(min.x, min.y, max.z),
            Vector3::new(max.x, max.y, min.z),
            Vector3::new(min.x, max.y, max.z),
            Vector3::new(max.x, min.y, max.z),
            Vector3::new(max.x, max.y, max.z),
        ];
        
        for corner in &corners {
            if self.contains_point(corner) {
                return true;
            }
        }
        false
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
}

/// A plane in 3D space
#[derive(Debug, Clone)]
pub struct Plane {
    pub normal: Vector3,
    pub distance: f32,
}

impl Plane {
    pub fn new(normal: Vector3, distance: f32) -> Self {
        Plane { normal, distance }
    }
    
    /// Signed distance from point to plane
    pub fn distance(&self, point: &Vector3) -> f32 {
        self.normal.dot(point) + self.distance
    }
}

/// Axis-aligned bounding box for spatial queries
#[derive(Debug, Clone)]
pub struct AABB {
    pub min: Vector3,
    pub max: Vector3,
}

impl AABB {
    /// Check if this AABB overlaps with another
    pub fn intersects(&self, other: &AABB) -> bool {
        self.min.x <= other.max.x && self.max.x >= other.min.x &&
        self.min.y <= other.max.y && self.max.y >= other.min.y &&
        self.min.z <= other.max.z && self.max.z >= other.min.z
    }
}

/// Octree node for spatial partitioning
struct OctreeNode {
    bounds: AABB,
    /// Indices of objects directly stored in this node (leaf or internal)
    object_indices: Vec<usize>,
    /// Child nodes (None if leaf)
    children: Option<Box<[Option<OctreeNode>; 8]>>,
}

impl OctreeNode {
    fn new(bounds: AABB) -> Self {
        OctreeNode {
            bounds,
            object_indices: Vec::new(),
            children: None,
        }
    }
    
    /// Insert an object into the octree node
    fn insert(&mut self, index: usize, aabb: &AABB) -> bool {
        // Check if AABB fits entirely within this node's bounds
        let center = Vector3::new(
            (self.bounds.min.x + self.bounds.max.x) * 0.5,
            (self.bounds.min.y + self.bounds.max.y) * 0.5,
            (self.bounds.min.z + self.bounds.max.z) * 0.5,
        );
        
        let size = Vector3::new(
            self.bounds.max.x - self.bounds.min.x,
            self.bounds.max.y - self.bounds.min.y,
            self.bounds.max.z - self.bounds.min.z,
        ) * 0.5;
        
        // If node is small enough or has too many objects, store here
        if size.length() < 1.0 || self.object_indices.len() > 8 {
            self.object_indices.push(index);
            return true;
        }
        
        // Determine which child to insert into
        let child_index = self.get_child_index(center);
        
        // Ensure children exist
        if self.children.is_none() {
            self.subdivide();
        }
        
        let children = self.children.as_mut().unwrap();
        
        if children[child_index].is_none() {
            children[child_index] = Some(OctreeNode::new(self.get_child_bounds(child_index)));
        }
        
        // Try to insert into child
        if let Some(ref mut child) = children[child_index] {
            return child.insert(index, aabb);
        }
        
        // If child is full, store in current node
        self.object_indices.push(index);
        true
    }
    
    fn get_child_index(&self, point: &Vector3) -> usize {
        let center = Vector3::new(
            (self.bounds.min.x + self.bounds.max.x) * 0.5,
            (self.bounds.min.y + self.bounds.max.y) * 0.5,
            (self.bounds.min.z + self.bounds.max.z) * 0.5,
        );
        
        let mut index = 0;
        if point.x > center.x { index |= 1; }
        if point.y > center.y { index |= 2; }
        if point.z > center.z { index |= 4; }
        
        index
    }
    
    fn subdivide(&mut self) {
        let min = self.bounds.min;
        let max = self.bounds.max;
        let mid = Vector3::new(
            (min.x + max.x) * 0.5,
            (min.y + max.y) * 0.5,
            (min.z + max.z) * 0.5,
        );
        
        self.children = Some(Box::new([None; 8]));
    }
    
    fn get_child_bounds(&self, index: usize) -> AABB {
        let min = self.bounds.min;
        let max = self.bounds.max;
        let mid_x = (min.x + max.x) * 0.5;
        let mid_y = (min.y + max.y) * 0.5;
        let mid_z = (min.z + max.z) * 0.5;
        
        AABB {
            min: Vector3::new(
                if index & 1 != 0 { mid_x } else { min.x },
                if index & 2 != 0 { mid_y } else { min.y },
                if index & 4 != 0 { mid_z } else { min.z },
            ),
            max: Vector3::new(
                if index & 1 != 0 { max.x } else { mid_x },
                if index & 2 != 0 { max.y } else { mid_y },
                if index & 4 != 0 { max.z } else { mid_z },
            ),
        }
    }
}

/// Octree root structure
pub struct Octree {
    root: Option<OctreeNode>,
    bounds: AABB,
}

impl Octree {
    pub fn new() -> Self {
        // Start with a large bounding box - will be adjusted based on scene content
        let default_bounds = AABB {
            min: Vector3::new(-1000.0, -1000.0, -1000.0),
            max: Vector3::new(1000.0, 1000.0, 1000.0),
        };
        
        Octree {
            root: Some(OctreeNode::new(default_bounds)),
            bounds: default_bounds,
        }
    }
    
    /// Insert an object into the octree
    pub fn insert(&mut self, index: usize, aabb: AABB) {
        if let Some(ref mut root) = self.root {
            root.insert(index, &aabb);
        }
    }
    
    /// Query all objects that might be visible in the given frustum
    pub fn query_frustum(
        &self,
        frustum: &Frustum,
        camera_position: &Vector3,
        callback: &mut dyn FnMut(usize),
    ) {
        if let Some(ref root) = self.root {
            Self::query_node(root, frustum, camera_position, callback);
        }
    }
    
    fn query_node(
        node: &OctreeNode,
        frustum: &Frustum,
        camera_position: &Vector3,
        callback: &mut dyn FnMut(usize),
    ) {
        // Check if this node's bounds are visible
        let min = node.bounds.min;
        let max = node.bounds.max;
        
        // Quick rejection test
        if !frustum.intersects_aabb(&min, &max) {
            return;
        }
        
        // Process objects stored in this node
        for &idx in &node.object_indices {
            callback(idx);
        }
        
        // Recurse into children if they exist
        if let Some(ref children) = node.children {
            for child in children.iter().flatten() {
                Self::query_node(child, frustum, camera_position, callback);
            }
        }
    }
}