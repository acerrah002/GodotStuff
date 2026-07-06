extends Node

signal lan_host_ready(ip: String, port: int)
signal lan_join_ready(ip: String, port: int)
signal lan_discovery_failed()

const DISCOVERY_PORT = 8912
const DISCOVERY_MESSAGE = "CTF_LAN_GAME"

var _udp_server: UDPServer = null
var _udp_client: PacketPeerUDP = null
var _is_hosting: bool = false

# LanManager is an autoload, so it can poll itself every frame.
# This fixes a bug where nothing was ever calling poll_discovery(),
# meaning a LAN host never actually answered join requests on any platform.
func _process(_delta: float) -> void:
	if _is_hosting:
		poll_discovery()

# ---------- Host a LAN game ----------
func host_lan(game_port: int = 8080) -> void:
	stop_lan()  # clean up any previous session so re-hosting doesn't fail
	_is_hosting = true
	var ip = _get_lan_ip()
	if ip == "":
		lan_discovery_failed.emit()
		return

	# Start a UDP server to respond to discovery requests
	_udp_server = UDPServer.new()
	if _udp_server.listen(DISCOVERY_PORT) != OK:
		lan_discovery_failed.emit()
		return

	lan_host_ready.emit(ip, game_port)

func poll_discovery() -> void:
	if _udp_server and _udp_server.is_connection_available():
		var peer: PacketPeerUDP = _udp_server.take_connection()
		var packet = peer.get_packet()
		if packet.get_string_from_ascii() == DISCOVERY_MESSAGE:
			var response = str(_get_lan_ip()) + ":" + str(8080)
			peer.put_packet(response.to_ascii_buffer())

# ---------- Join a LAN game ----------
func join_lan(game_port: int = 8080) -> void:
	if _udp_client:
		_udp_client.close()
		_udp_client = null

	_udp_client = PacketPeerUDP.new()
	# CRITICAL for cross-platform: without enabling broadcast explicitly,
	# macOS/Linux drop outgoing broadcast packets and Android blocks them.
	_udp_client.set_broadcast_enabled(true)
	if _udp_client.set_dest_address("255.255.255.255", DISCOVERY_PORT) != OK:
		lan_discovery_failed.emit()
		return

	_udp_client.put_packet(DISCOVERY_MESSAGE.to_ascii_buffer())
	await get_tree().create_timer(1.0).timeout
	var response = _udp_client.get_packet()
	if response.size() > 0:
		var parts = response.get_string_from_ascii().split(":")
		if parts.size() == 2:
			lan_join_ready.emit(parts[0], int(parts[1]))
			return
	lan_discovery_failed.emit()

# ---------- Cleanup ----------
func stop_lan() -> void:
	_is_hosting = false
	if _udp_server:
		_udp_server.stop()
		_udp_server = null
	if _udp_client:
		_udp_client.close()
		_udp_client = null

# ---------- Helper ----------
func _get_lan_ip() -> String:
	var interfaces = IP.get_local_addresses()
	for iface in interfaces:
		if iface.begins_with("192.168.") or iface.begins_with("10.") or iface.begins_with("172."):
			return iface
	return "127.0.0.1"
