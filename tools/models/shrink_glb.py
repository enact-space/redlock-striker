"""Make a phone-sized copy of a character GLB: every embedded texture is scaled down to at most
MAX px (default 1024) and stored as PNG (if it has alpha) or JPEG. Geometry, rig, skin weights and
animations are copied byte for byte. The original file is never touched.

Usage: python3 -I shrink_glb.py IN.glb OUT.glb [MAX]
"""
import io, json, struct, sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
MAX = int(sys.argv[3]) if len(sys.argv) > 3 else 1024

data = open(src, "rb").read()
magic, ver, total = struct.unpack_from("<III", data, 0)
assert magic == 0x46546C67, "not a GLB"
jlen, jtype = struct.unpack_from("<II", data, 12)
gltf = json.loads(data[20:20 + jlen])
off = 20 + jlen
blen, btype = struct.unpack_from("<II", data, off)
binc = data[off + 8: off + 8 + blen]

views = gltf["bufferViews"]
newdata = {}
for img in gltf.get("images", []):
    bv = img["bufferView"]
    v = views[bv]
    raw = binc[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
    im = Image.open(io.BytesIO(raw))
    im.load()
    if max(im.size) > MAX:
        s = MAX / max(im.size)
        im = im.resize((max(1, round(im.size[0] * s)), max(1, round(im.size[1] * s))), Image.LANCZOS)
    alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
    if alpha:
        im = im.convert("RGBA")
        if im.getchannel("A").getextrema()[0] == 255:
            alpha = False
    out = io.BytesIO()
    if alpha:
        im.save(out, "PNG", optimize=True)
        img["mimeType"] = "image/png"
    else:
        im.convert("RGB").save(out, "JPEG", quality=90)
        img["mimeType"] = "image/jpeg"
    newdata[bv] = out.getvalue()
    print(f"{img.get('name')}: {len(raw)} -> {len(newdata[bv])} bytes, {im.size}")

# webp textures now point at plain PNG/JPEG images
for tex in gltf.get("textures", []):
    ext = tex.get("extensions", {})
    if "EXT_texture_webp" in ext:
        tex["source"] = ext["EXT_texture_webp"]["source"]
        del ext["EXT_texture_webp"]
        if not ext:
            del tex["extensions"]
for key in ("extensionsUsed", "extensionsRequired"):
    if key in gltf:
        gltf[key] = [e for e in gltf[key] if e != "EXT_texture_webp"]
        if not gltf[key]:
            del gltf[key]

# repack the binary chunk view by view (4-byte aligned)
out = bytearray()
for i, v in enumerate(views):
    chunk = newdata.get(i)
    if chunk is None:
        o = v.get("byteOffset", 0)
        chunk = binc[o: o + v["byteLength"]]
    while len(out) % 4:
        out.append(0)
    v["byteOffset"] = len(out)
    v["byteLength"] = len(chunk)
    out += chunk
while len(out) % 4:
    out.append(0)
gltf["buffers"][0]["byteLength"] = len(out)

js = json.dumps(gltf, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out))
glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(out), 0x004E4942) + bytes(out)
open(dst, "wb").write(glb)
print(f"{src}: {len(data)} -> {len(glb)} bytes")
