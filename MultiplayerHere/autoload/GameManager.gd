extends Node

# NOTE: Player scene not wired up yet. This is a stub so lobby -> start game
# flow works end-to-end without needing a player_character.tscn.

func spawn_all_players():
	print("[GameManager] spawn_all_players called (stub - no player scene yet).")
	for id in NetworkManager.players:
		var data = NetworkManager.players[id]
		rpc("_spawn_player", id, data.name)

@rpc("authority", "reliable")
func _spawn_player(peer_id: int, pname: String):
	print("[GameManager] Would spawn player for peer ", peer_id, " name ", pname, " (skipped - no player scene set up).")
	# TODO: once you have a player scene, re-add instancing logic here, e.g.:
	# var player = PLAYER_SCENE.instantiate()
	# player.name = str(peer_id)
	# player.set_multiplayer_authority(peer_id)
	# get_tree().root.add_child(player)
