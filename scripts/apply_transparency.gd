
extends Node3D

# Script to apply transparency shader to collision objects
# Run this in the editor or attach to objects that need occlusion transparency

@export var material: ShaderMaterial = null
@export var fade_distance: float = 1.0
@export var enable_on_ready: bool = true
@export var enabled: bool = true

@onready var mesh = $MeshInstance3D
@onready var collision = $CollisionShape3D

func _ready() -> void:
    apply_transparency()
    
func apply_transparency() -> void:
    if not enabled:
        return
    
    var shader = load("res://shaders/transparency_material.gdshader").new()
    var mat = ShaderMaterial.new()
    mat.shader = shader
    mat.set("shader_parameter/fade_distance", fade_distance)
    mat.set("shader_parameter/opacity", 0.7)  # 70% opacity
    
    if mesh != null:
        mesh.material_override = mat
    else:
        # Look for mesh instance in children
        for child in get_children():
            if child is MeshInstance3D:
                child.material_override = mat
    
    print("Transparency material applied to: ", name)
