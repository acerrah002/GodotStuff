extends Node

signal lan_host_ready(ip: String, port: int)
signal lan_join_ready(ip: String, port: int)
signal lan_discovery_failed()

const DISCOVERY_PORT = 8912
const DISCOVERY_MESSAGE = "CTF_LAN_GAME"

var _udp_server: UDPServer = null
var _udp_client: PacketPeerUDP = null
var _is_hosting: bool = false

# ---------- Host a LAN game ----------
func host_lan(game_port: int = 8080) -> void:
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

# Call this every frame (best done from an autoload _process)
func poll_discovery() -> void:
	if _udp_server and _udp_server.is_connection_available():
		var peer: PacketPeerUDP = _udp_server.take_connection()
		var packet = peer.get_packet()
		if packet.get_string_from_ascii() == DISCOVERY_MESSAGE:
			# Respond with the game port (you could send the IP too)
			var response = str(_get_lan_ip()) + ":" + str(8080)   # actual game port
			peer.put_packet(response.to_ascii_buffer())

# ---------- Join a LAN game ----------
func join_lan(game_port: int = 8080) -> void:
	_udp_client = PacketPeerUDP.new()
	if _udp_client.set_dest_address("255.255.255.255", DISCOVERY_PORT) != OK:
		lan_discovery_failed.emit()
		return

	_udp_client.put_packet(DISCOVERY_MESSAGE.to_ascii_buffer())
	# Wait a moment for responses (you could use a timer)
	await get_tree().create_timer(1.0).timeout
	var response = _udp_client.get_packet()
	if response.size() > 0:
		var parts = response.get_string_from_ascii().split(":")
		if parts.size() == 2:
			lan_join_ready.emit(parts[0], int(parts[1]))
			return
	lan_discovery_failed.emit()

# ---------- Helper ----------
func _get_lan_ip() -> String:
	var interfaces = IP.get_local_addresses()
	for iface in interfaces:
		if iface.begins_with("192.168.") or iface.begins_with("10.") or iface.begins_with("172."):
			return iface
	return "127.0.0.1"
