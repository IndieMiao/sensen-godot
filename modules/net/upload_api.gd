class_name UploadApi
extends RefCounted
## D4-c 客户端：向服务端要预签名 PUT 地址，再把字节直接放上去。服务端本地模式与 R2 形状一样，
## 客户端不区分；读图统一用 Net.file_url(key)。返回格式同 AccountApi.wrap_response。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

func presign(kind: String, content_type: String, size: int) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/uploads", {"kind": kind, "content_type": content_type, "size": size}))

## 上传一张 ImagePrep 预处理过的图（{bytes, mime, width, height}）。返回 {ok, key, w, h, public_url} 或 {ok:false, code}。
func upload_image(item: Dictionary, kind := "post_image") -> Dictionary:
	var bytes: PackedByteArray = item.get("bytes", PackedByteArray())
	if bytes.is_empty():
		return {"ok": false, "code": "EMPTY"}
	var p: Dictionary = await presign(kind, str(item.get("mime", "image/jpeg")), bytes.size())
	if not bool(p.get("ok", false)):
		return p
	var headers := PackedStringArray()
	var hs = p.get("headers", {})
	if hs is Dictionary:
		for k in hs:
			headers.append("%s: %s" % [str(k), str(hs[k])])
	var r: ApiClient.Response = await client.put_bytes(str(p.get("url", "")), headers, bytes)
	if not r.is_success():
		return {"ok": false, "code": r.code() if r.ok else "NETWORK", "status": r.status}
	return {"ok": true, "key": str(p.get("key", "")), "w": int(item.get("width", 0)), "h": int(item.get("height", 0)), "public_url": str(p.get("public_url", ""))}

## 多张顺序上传；任一失败整体失败，带上已成功的张数（uploaded）。成功返回 {ok, images: [{key, w, h}]}。
func upload_images(items: Array, kind := "post_image") -> Dictionary:
	var out: Array = []
	for it in items:
		var r: Dictionary = await upload_image(it, kind)
		if not bool(r.get("ok", false)):
			r["uploaded"] = out.size()
			return r
		out.append({"key": r.key, "w": r.w, "h": r.h})
	return {"ok": true, "images": out}
