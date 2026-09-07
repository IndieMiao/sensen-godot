extends GdUnitTestSuite
## UploadApi：presign 再把字节 PUT 到给回的地址（带回的 headers 原样带上）；PUT 失败 / presign 失败都报出来；多张顺序上传遇错即停。

var t: FakeTransport
var raw_calls: Array = []
var raw_status := 200

func before_test() -> void:
	t = FakeTransport.new([])
	raw_calls = []
	raw_status = 200

func _api() -> UploadApi:
	var c := ApiClient.new("https://example.test/v1", t.callable())
	c.raw_transport = func(method: String, url: String, headers: PackedStringArray, bytes: PackedByteArray) -> ApiClient.Response:
		raw_calls.append({"method": method, "url": url, "headers": headers, "size": bytes.size()})
		return ApiClient.Response.new(true, raw_status, {}, "")
	return UploadApi.new(c)

func _presigned(key: String) -> Dictionary:
	return {"key": key, "url": "http://host/v1/uploads/local/tok-%s" % key, "method": "PUT", "headers": {"content-type": "image/jpeg"}, "expires_at": 1, "public_url": "http://host/v1/files/%s" % key}

func test_upload_image_presigns_then_puts_bytes_with_headers() -> void:
	t.responses = [{"status": 201, "json": _presigned("u/me/20260907/a.jpg")}]
	var r: Dictionary = await _api().upload_image({"bytes": PackedByteArray([1, 2, 3]), "mime": "image/jpeg", "width": 30, "height": 20})
	assert_bool(r.ok).is_true()
	assert_str(r.key).is_equal("u/me/20260907/a.jpg")
	assert_int(r.w).is_equal(30)
	# FakeTransport 经 JSON 往返，数字成了 float：逐字段比
	assert_str(str(t.requests[0].body.kind)).is_equal("post_image")
	assert_str(str(t.requests[0].body.content_type)).is_equal("image/jpeg")
	assert_int(int(t.requests[0].body.size)).is_equal(3)
	assert_str(raw_calls[0].method).is_equal("PUT")
	assert_str(raw_calls[0].url).is_equal("http://host/v1/uploads/local/tok-u/me/20260907/a.jpg")
	assert_array(Array(raw_calls[0].headers)).is_equal(["content-type: image/jpeg"])
	assert_int(raw_calls[0].size).is_equal(3)

func test_upload_image_reports_presign_and_put_failures() -> void:
	t.responses = [{"status": 503, "json": {"code": "UPLOADS_NOT_CONFIGURED"}}, {"status": 201, "json": _presigned("k")}]
	var api := _api()
	var a: Dictionary = await api.upload_image({"bytes": PackedByteArray([1]), "mime": "image/jpeg"})
	assert_bool(a.ok).is_false()
	assert_str(a.code).is_equal("UPLOADS_NOT_CONFIGURED")
	raw_status = 413
	var b: Dictionary = await api.upload_image({"bytes": PackedByteArray([1]), "mime": "image/jpeg"})
	assert_bool(b.ok).is_false()
	assert_str(b.code).is_equal("HTTP_413")
	var e: Dictionary = await api.upload_image({"bytes": PackedByteArray(), "mime": "image/jpeg"})
	assert_str(e.code).is_equal("EMPTY")

func test_upload_images_stops_at_first_failure_and_reports_progress() -> void:
	t.responses = [{"status": 201, "json": _presigned("k1")}, {"status": 201, "json": _presigned("k2")}, {"error": "timeout"}]
	var items := [{"bytes": PackedByteArray([1]), "mime": "image/jpeg", "width": 1, "height": 1}, {"bytes": PackedByteArray([2]), "mime": "image/jpeg", "width": 2, "height": 2}, {"bytes": PackedByteArray([3]), "mime": "image/jpeg"}]
	var r: Dictionary = await _api().upload_images(items)
	assert_bool(r.ok).is_false()
	assert_int(r.uploaded).is_equal(2)
	t.responses.append({"status": 201, "json": _presigned("k3")})
	t.responses.append({"status": 201, "json": _presigned("k4")})
	var ok: Dictionary = await _api().upload_images(items.slice(0, 2))
	assert_bool(ok.ok).is_true()
	assert_that(ok.images).is_equal([{"key": "k3", "w": 1, "h": 1}, {"key": "k4", "w": 2, "h": 2}])
