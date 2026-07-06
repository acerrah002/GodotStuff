extends Node

signal discovery_completed(success: bool)
signal port_mapped(port: int, success: bool)
signal port_unmapped(port: int, success: bool)

var _upnp: UPNP = null
var external_ip: String = ""
var _mapped_ports: Array = []

func discover() -> void:
	# NOTE: on Android, most carrier/mobile networks and many WiFi routers
	# don't expose a UPnP gateway at all, so this will usually just fail
	# gracefully and emit discovery_completed(false). That's expected -
	# LAN mode is the more reliable option on mobile.
	_upnp = UPNP.new()
	var result = _upnp.discover()
	if result == UPNP.UPNP_RESULT_SUCCESS:
		external_ip = _upnp.query_external_address()
		print("[Upnp] Discovery success. External IP: ", external_ip)
		discovery_completed.emit(true)
	else:
		print("[Upnp] Discovery failed (code %d)" % result)
		discovery_completed.emit(false)

func open_port(port: int, description: String = "Godot Game") -> bool:
	if not _upnp or not _upnp.get_gateway():
		print("[Upnp] No gateway")
		return false

	if _upnp.add_port_mapping(port, 0, description, "UDP") == UPNP.UPNP_RESULT_SUCCESS:
		_mapped_ports.append({"port": port, "desc": description})
		print("[Upnp] Port %d opened" % port)
		port_mapped.emit(port, true)
		return true
	else:
		print("[Upnp] Failed to open port %d" % port)
		port_mapped.emit(port, false)
		return false

func close_port(port: int) -> bool:
	if not _upnp: return false
	if _upnp.delete_port_mapping(port, "UDP") == UPNP.UPNP_RESULT_SUCCESS:
		_mapped_ports = _mapped_ports.filter(func(m): return m.port != port)
		print("[Upnp] Port %d closed" % port)
		port_unmapped.emit(port, true)
		return true
	print("[Upnp] Failed to close port %d" % port)
	port_unmapped.emit(port, false)
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_cleanup_all()

func _cleanup_all() -> void:
	for mapping in _mapped_ports.duplicate():
		close_port(mapping.port)
