extends Node

# Signals
signal bt_host_ready(port: int)
signal bt_join_ready(address: String, port: int)
signal bt_discovery_failed()

# ---------- Host a Bluetooth game ----------
func host_bt(game_port: int = 8080) -> void:
	# Real implementation: create a Bluetooth server socket
	# using Godot's Bluetooth class (if available on your platform).
	# For now, just signal readiness.
	bt_host_ready.emit(game_port)

# ---------- Join a Bluetooth game ----------
func join_bt(address: String = "", game_port: int = 8080) -> void:
	# Real implementation: scan for Bluetooth devices, pair, connect.
	# For now, use a placeholder or the provided address.
	if address == "":
		address = "00:00:00:00:00:00"   # placeholder
	bt_join_ready.emit(address, game_port)
