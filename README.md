# Paintable Stuff

Project Zomboid mod to enable items to be repainted in-game.

## Making items paintable

### Creating a TINT mask

This mod uses the game's tinting feature, used in vanilla for clothing, umbrellas, decor items, ...  
By default the tint is applied to the object as a solid colour overlay. To apply the tint in a visually appealing way a TINT mask needs to be created.  
The file should have the same name as the texture it should be applied to, eg:  
```
Item: Base.Crowbar
Texture: Crowbar.png
Tint mask: CrowbarTINT.png
```

The mask uses the same texture mapping as the model's texture. Software like blender can be used to visualise and paint the texture.

Your mask texture should have an alpha channel.

The alpha channel is used to define the opacity of the applied tint. Fully transparent areas of the mask are therefore unaffected by the tint.
The RGB values define the brightness of the tint; [0,0,0] becomes fully black, [255,255,255] matches the tint colour. A value in between will darken the tint colour on that pixel.

Place the mask in the directory which you would use to override/set the item's texture, eg:
```
Item: Base.Crowbar
Texture path: [ZOMBOID_DIR]/media/textures/weapons/1handed/CrowbarTINT.png
Mask path: [MOD_DIR]/media/textures/weapons/1handed/CrowbarTINT.png
```

### Custom world model

A custom world model is needed for certain items, without it the tint mask is ignored when the item is placed in the world.  
If your items need this, a custom world model can be generated with [gen_world_models.py](./scripts/gen_world_models.py).  
The custom world models file should be placed in ```media/scripts```

### Registering paintable items

To register an item as paintable, the PaintableStuff API needs to be used, eg:
```lua
require "TS_PaintableStuff/tsPaintStuffApi"

TS_PaintStuff.registerPaintable("Base.Crowbar", { index = 0, worldPainted = "TS_CrowbarWorldPaint" })
```

#### Function usage:

```lua
function registerPaintable(fullType, opts)
```
- fullType: typename of item
-  opts: optional parameters
-  opts.index: modelIndex to make paintable, used for items with multiple visual variants, default is 0.  
After removing paint, the item's modelIndex will be reset to it's original state.
- opts.worldPainted: custom ground to apply to this item.  
If not set, the default ground model will be used and vanilla items will ignore the tint mask when placed in the world.  
The custom world models can be generated with [gen_world_models.py](./scripts/gen_world_models.py)
- opts.worldPaintedBySprite: optional table mapping the item's current model (`item:getStaticModel()`) to a ground
model. It is checked before `worldPainted`. Use it when another mod swaps the item's model, for example an
empty-magazine variant:
```lua
TS_PaintStuff.registerPaintable("Base.AssaultRifle", {
    worldPainted = "TS_AssaultRifleWorldPaint",
    worldPaintedBySprite = {
        PZRA_M16_NoMag = "TS_PZRA_M16_NoMagWorldPaint",
    },
})
```

If a variant model comes from another mod, generate its world model with `--extra-model-script` and `--extra-model`:
```
python3 scripts/gen_world_models.py Base.AssaultRifle \
    --extra-model-script /path/to/OtherMod/scripts/other_models.txt \
    --extra-model PZRA_M16_NoMag \
    --out media/scripts/myWorldModels.txt
```

### See my mods for examples:
- [Paintable Stuff - Tools](https://github.com/Bas-W/zomboid_paintableStuff_tools)  
- [Paintable Stuff - Weapons](https://github.com/Bas-W/zomboid_paintableStuff_weapons)