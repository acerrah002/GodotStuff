extends Node

const PLAYER_SCENE = preload("res://Scenes/player_character.tscn")

func spawn_all_players():
	print("[GameManager] Spawning players for all peers...")
	for id in NetworkManager.players:
		var data = NetworkManager.players[id]
		rpc("_spawn_player", id, data.name, data.team)

@rpc("authority", "reliable")
func _spawn_player(peer_id: int, pname: String, team: int):
	print("[GameManager] Spawning player for peer ", peer_id, " name ", pname, " team ", team)
	if has_node("/root/" + str(peer_id)):
		return
	var player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.team = team
	get_tree().root.add_child(player)
	player.apply_team_color()
