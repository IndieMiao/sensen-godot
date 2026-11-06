"""Museum roof decoration in Godot metres; retain the 40 x 10 x 9 m envelope."""
import bpy
from landmark_kit import hex_rgb

COLORS = {
    'museum_roof_slate': '748B9C',
    'museum_roof_cream': 'F0E1C2',
    'museum_skylight_blue': 'A9D5DF',
    'museum_skylight_shade': '7FAEBE',
    'museum_skylight_glint': 'D7EDF0',
    'museum_vent_shadow': '526C7C',
}
SKYLIGHT_CENTRES = [(-12, 0.6), (0, 0.6), (12, 0.6)]
VENT_CENTRES = [(-16.3, -2.5), (16.3, -2.5)]


def is_roof_part(name):
    return name.startswith(('roof_', 'recessed_roof', 'vent_shadow', 'museum_skylight_'))


def build(kit, box):
    for name, rgb in COLORS.items():
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.diffuse_color = (*hex_rgb(rgb), 1)
        kit.mats[name] = mat
    cream = 'museum_roof_cream'
    # Existing slab/parapet dimensions and local pivot are retained.
    box('roof_slab', (0, 8.48, 0), (40, .20, 10), cream, .02)
    box('recessed_roof', (0, 8.60, 0), (39.1, .06, 9.1), 'museum_roof_slate', 0)
    for z in [-4.84, 4.84]:
        box('roof_parapet', (0, 8.77, z), (40, .26, .32), cream, .02)
        box('roof_coping_long', (0, 8.93, z), (40, .06, .32), cream, .015)
    for x in [-19.84, 19.84]:
        box('roof_parapet_end', (x, 8.77, 0), (.32, .26, 9.4), cream, .02)
        box('roof_coping_end', (x, 8.93, 0), (.32, .06, 9.36), cream, .015)
    for i, (x, z) in enumerate(SKYLIGHT_CENTRES, 1):
        prefix = 'museum_skylight_%d_' % i
        box(prefix+'curb', (x, 8.66, z), (3.8, .08, 2.0), cream, .015)
        # A low pitched skylight: broad blue panes, no transparency/pass or grids.
        for sign in [-1, 1]:
            edge_z = z + sign*.87
            pane = [(x-1.75, 8.72, edge_z), (x+1.75, 8.72, edge_z),
                    (x+1.75, 8.96, z), (x-1.75, 8.96, z)]
            if sign < 0:
                pane.reverse()
            kit.mesh(prefix+('front_pane' if sign > 0 else 'back_pane'), pane,
                     [(0, 1, 2, 3)], 'museum_skylight_blue' if sign > 0 else 'museum_skylight_shade')
            box(prefix+'eave', (x, 8.72, edge_z), (3.62, .045, .055), cream, 0)
            for side in [-1, 1]:
                # Thin top strips avoid invisible bevels at this screen scale.
                strip = [(x+side*1.78-.03, 8.725, edge_z),
                         (x+side*1.78+.03, 8.725, edge_z),
                         (x+side*1.78+.03, 8.965, z),
                         (x+side*1.78-.03, 8.965, z)]
                if sign < 0:
                    strip.reverse()
                kit.mesh(prefix+'rake', strip, [(0, 1, 2, 3)], cream)
        box(prefix+'ridge', (x, 8.975, z), (3.62, .05, .055), cream, 0)
        for side in [-1, 1]:
            points = [(x+side*1.75, 8.72, z-.87), (x+side*1.75, 8.72, z+.87),
                      (x+side*1.75, 8.96, z)]
            if side > 0:
                points.reverse()
            kit.mesh(prefix+'gable', points, [(0, 1, 2)], 'museum_skylight_shade')
        # A single broad reflected-sky patch reads at the farm camera scale.
        def front_y(pz):
            return 8.96-(pz-z)*(.24/.87)+.002
        glint = [(x-1.35, z+.15), (x-.75, z+.15), (x+.10, z+.72), (x-.65, z+.72)]
        kit.mesh(prefix+'sky_reflection', [(px, front_y(pz), pz) for px, pz in reversed(glint)],
                 [(0, 1, 2, 3)], 'museum_skylight_glint')
    for i, (x, z) in enumerate(VENT_CENTRES, 1):
        box('roof_vent_%d_body' % i, (x, 8.79, z), (.64, .30, .64), cream, .02)
        box('roof_vent_%d_cap' % i, (x, 8.97, z), (.82, .06, .82), cream, .012)
        box('roof_vent_%d_inset' % i, (x, 8.82, z+.326), (.38, .095, .012),
            'museum_vent_shadow', 0)
