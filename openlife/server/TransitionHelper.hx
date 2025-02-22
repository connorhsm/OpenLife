package openlife.server;

import format.hl.Data.CodeFlag;
import openlife.data.object.ObjectData;
import openlife.data.object.ObjectHelper;
import openlife.data.transition.TransitionData;
import openlife.data.transition.TransitionImporter;
import openlife.macros.Macro;
import openlife.server.GlobalPlayerInstance.Emote;
import openlife.settings.ServerSettings;

using StringTools;

class TransitionHelper {
	public var x:Int;
	public var y:Int;

	public var tx:Int;
	public var ty:Int;

	public var player:GlobalPlayerInstance;

	// public var index:Int = -1; // Index in container or clothing index in case of drop
	// public var handObject:Array<Int>;
	// public var tileObject:Array<Int>;
	public var floorId:Int;
	public var transitionSource:Int;

	// public var newHandObject:Array<Int>;
	// public var newTileObject:Array<Int>;
	public var newFloorId:Int;
	public var newTransitionSource:Int;

	public var target:ObjectHelper;

	public var handObjectData:ObjectData;
	public var tileObjectData:ObjectData;

	// if a transition is done, the MX (MAPUPDATE) needs to send a negative palyer id to indicate that its not a drop
	public var doTransition:Bool = true;
	public var doAction:Bool;
	public var pickUpObject:Bool = false;

	public static function doCommand(player:GlobalPlayerInstance, tag:ServerTag, x:Int, y:Int, index:Int = -1, target:Int = 0):Bool {
		// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} doCommand try to acquire player mutex');
		GlobalPlayerInstance.AllPlayerMutex.acquire();
		// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} doCommand try to acquire map mutex');
		Server.server.map.mutex.acquire();
		// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} doCommand got all mutex');

		var done = false;
		Macro.exception(done = doCommandHelper(player, tag, x, y, index, target));
		if (done == false) {
			// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} WARNING: ' + e);
			// send PU so that player wont get stuck
			player.connection.send(PLAYER_UPDATE, [player.toData()]);
			player.connection.send(FRAME);
		}

		// if(ServerSettings.DebugTransitionHelper) trace("release map mutex");
		Server.server.map.mutex.release();
		// if(ServerSettings.DebugTransitionHelper) trace("release player mutex");
		GlobalPlayerInstance.AllPlayerMutex.release();

		return done;
	}

	public static function doCommandHelper(player:GlobalPlayerInstance, tag:ServerTag, x:Int, y:Int, index:Int = -1, target:Int = 0):Bool {
		var helper = new TransitionHelper(player, x, y);

		if ((player.o_id[0] < 0) || player.heldPlayer != null) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} cannot do use since holding a player! ${player.o_id[0]}');
			helper.sendUpdateToClient();
			// player.dropPlayer();
			return false;
		}

		// if(player.heldObject.isPermanent() || player.heldObject.isNeverDrop())
		if (player.heldObject.isNeverDrop()) {
			// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id}'HeldObject is permanent ${player.heldObject.isPermanent()} or cannot be dropped! ${player.heldObject.isNeverDrop()}');
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} HeldObject cannot be dropped!');
			helper.sendUpdateToClient();

			var time = player.heldObject.timeToChange - TimeHelper.CalculateTimeSinceTicksInSec(player.heldObject.creationTimeInTicks);
			if (time > 0) player.say('${Math.ceil(time)} seconds...', true);
			return false;
		}

		if (player.heldObject.isWound()) {
			// you can still do things with a hiddenwound
			if (player.heldObject == player.hiddenWound) {
				player.setHeldObject(null);
			} else {
				// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} HeldObject is permanent ${player.heldObject.isPermanent()} or cannot be dropped! ${player.heldObject.isNeverDrop()}');
				if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} HeldObject is a wound!');
				helper.sendUpdateToClient();
				var time = player.heldObject.timeToChange - TimeHelper.CalculateTimeSinceTicksInSec(player.heldObject.creationTimeInTicks);
				if (time > 0) player.say('${Math.ceil(time)} seconds...', true);
				return false;
			}
		}

		if (player.killMode) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} kill mode deactivated try again!');
			helper.sendUpdateToClient();
			player.killMode = false;
			return false;
		}

		if (ServerSettings.AllyStrenghTooLowForPickup > 0) {
			var allyStrengh = player.calculateEnemyVsAllyStrengthFactor();
			if (allyStrengh < ServerSettings.AllyStrenghTooLowForPickup && helper.target.id != 0) // allow if target is empty
			{
				player.say('Too many hostile people...', true);
				helper.sendUpdateToClient();
				return false;
			}
		}

		if (player.isMyGrave(helper.target)) {
			player.say('Its my grave...', true);
			helper.sendUpdateToClient();
			return false;
		}

		switch (tag) {
			case USE:
				helper.use(target, index);
			case DROP:
				helper.drop(index);
			case REMV:
				helper.remove(index);
			default:
		}

		helper.sendUpdateToClient();

		return helper.doAction;
	}

	public function new(player:GlobalPlayerInstance, x:Int, y:Int) {
		this.player = player;

		this.x = x;
		this.y = y;

		this.tx = x + player.gx;
		this.ty = y + player.gy;

		// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} $ $ t$ p$');

		this.floorId = Server.server.map.getFloorId(tx, ty);
		this.transitionSource = player.o_transition_source_id;

		this.newFloorId = this.floorId;
		this.newTransitionSource = this.transitionSource;

		// ObjectHelpers are for storing advanced dato like USES, CREATION TIME, OWNER
		this.target = Server.server.map.getObjectHelper(tx, ty);

		this.handObjectData = player.heldObject.objectData;
		this.tileObjectData = target.objectData;

		// dummies are objects with numUses > 1 numUse = maxUse is the original
		if (tileObjectData.dummy) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} is dummy: ${tileObjectData.description} dummyParent: ${tileObjectData.dummyParent.description}');
			tileObjectData = tileObjectData.dummyParent;
		}

		// if(ServerSettings.DebugTransitionHelper) trace("hand: " + this.handObject + " tile: " + this.tileObject + ' tx: $tx ty:$ty');

		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} isAI: ${player.isAi()} AGE: ${player.age}');
		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} handObjectHelper: ${handObjectData.description} numberOfUses: ${player.heldObject.numberOfUses} '
			+ player.heldObject.toArray());
		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} target: ${tileObjectData.description} ${target.tx}, ${target.ty} numberOfUses: ${target.numberOfUses} '
			+ target.toArray());
	}

	/*
		DROP x y c#

		DROP is for setting held object down on empty grid square OR
		 for adding something to a container
		 c is -1 except when adding something to own clothing, then c
		 indicates clothing with:
		 0=hat, 1=tunic, 2=frontShoe, 3=backShoe, 4=bottom, 5=backpack */
	public function drop(clothingIndex:Int = -1):Bool {
		if (ServerSettings.DebugTransitionHelper) trace('DROP: ${player.name + player.id} ${player.name + player.id} clothingIndex: $clothingIndex');
		// this is a drop and not a transition
		this.doTransition = false;

		if (player.heldPlayer != null) {
			var message = 'DROP: ${player.name + player.id} WARNING: Drop player should be handled by GlobalPlayer.dropPlayer() not drop for objects!!!';

			trace(message);

			throw(message);
		}

		if (clothingIndex >= 0) return player.doPlaceObjInClothing(clothingIndex, true);

		if (this.tileObjectData.minPickupAge - ServerSettings.ReduceAgeNeededToPickupObjects > player.age) {
			if (ServerSettings.DebugTransitionHelper)
				trace('DROP: ${player.name + player.id} TOO young to pickup: target.minPickupAge: ${tileObjectData.minPickupAge} player.age: ${player.age}');
			return false;
		}

		// if target cointains item, then dont reduce pickup age
		if (this.target.containedObjects.length > 0 && this.tileObjectData.minPickupAge > player.age) {
			if (ServerSettings.DebugTransitionHelper)
				trace('DROP: ${player.name + player.id} Container: TOO young to pickup: target.minPickupAge: ${tileObjectData.minPickupAge} player.age: ${player.age}');
			return false;
		}

		if (this.checkIfNotMovingAndCloseEnough() == false) return false;

		// switch hand object in container with last object in container
		if (this.doContainerStuff(true)) return true;

		return this.swapHandAndFloorObject();
	}

	public function checkIfNotMovingAndCloseEnough():Bool {
		if (player.moveHelper.isMoveing()) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Player is still moving');
			return false;
		}

		var useDistance = player.heldObject.objectData.useDistance;

		if (useDistance < 1) useDistance = 1;

		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} ${player.heldObject.description} useDistance: $useDistance');

		if (player.isClose(x, y, useDistance) == false) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Object position is too far away p${player.x},p${player.y} o$x,o$y');
			return false;
		}

		return true;
	}

	// DROP switches the object with the last object in the container and cycles throuh the objects / USE just put it in
	public function doContainerStuff(isDrop:Bool = false, index:Int = -1):Bool {
		if (DoContainerStuffOnObj(this.player, target, isDrop, index)) {
			this.pickUpObject = true;
			this.doAction = true;
			return true;
		}

		return false;
	}

	public static function DoContainerStuffOnObj(player:GlobalPlayerInstance, container:ObjectHelper, isDrop:Bool = false, index:Int = -1):Bool {
		var objToStore:ObjectHelper = player.heldObject;
		var containerObjData = container.objectData;
		var objToStoreObjData = objToStore.objectData;

		if (ServerSettings.DebugTransitionHelper) trace("Container: " + containerObjData.description + "containable: " + containerObjData.containable
			+ " numSlots: " + containerObjData.numSlots);

		// TODO change container check
		// if ((objectData.numSlots == 0 || MapData.numSlots(this.tileObject) >= objectData.numSlots)) return false;
		if (containerObjData.numSlots == 0) return false;

		var amountOfContainedObjects = container.containedObjects.length;

		// if hand is empty then remove last object from container
		if (objToStore.id == 0 && amountOfContainedObjects > 0) {
			if (ServerSettings.DebugTransitionHelper) trace("REMOVE");

			if (index < 0) index = 0;

			// cannot pickup Threshed Wheat from Table
			if (container.containedObjects[index].objectData.permanent == 1) return false;

			player.setHeldObject(container.removeContainedObject(index));

			// if(remove(index)) return true;
			return true;
		}

		if (objToStoreObjData.containable == false) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} handObject is not containable!');
			return false;
		}

		// place hand object in container if container has enough space
		// if (handObjectData.slotSize >= objectData.containSize) {
		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} Container: ${objToStore.description} objToStore.slotSize: ${objToStoreObjData.slotSize} container.containSize: ${containerObjData.containSize}');
		if (objToStoreObjData.slotSize > containerObjData.containSize) return false;

		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} Container: ${objToStore.description} objToStore.slotSize: ${objToStoreObjData.slotSize} TO: container.containSize: ${containerObjData.containSize}');

		if (isDrop == false) {
			if (container.id == 87 || container.id == 88) return false; // 87 = Fresh Grave 88 = grave // connot place in grave

			if (amountOfContainedObjects >= containerObjData.numSlots) return false;

			container.containedObjects.push(player.heldObject);

			player.setHeldObject(null);

			return true;
		}

		var tmpObject = container.removeContainedObject(-1);

		container.containedObjects.insert(0, player.heldObject);

		player.setHeldObject(tmpObject);

		if (ServerSettings.DebugTransitionHelper) trace('DROP SWITCH Hand object: ${player.heldObject.toArray()}');
		if (ServerSettings.DebugTransitionHelper) trace('DROP SWITCH New Tile object: ${container.toArray()}');

		return true;
	}

	private function swapHandAndFloorObject():Bool {
		// if(ServerSettings.DebugTransitionHelper) trace("SWAP tileObjectData: " + tileObjectData.toFileString());

		var permanent = (tileObjectData != null) && (tileObjectData.permanent == 1);

		if (permanent) return false;

		var tmpTileObject = target;

		this.target = this.player.heldObject;
		this.player.setHeldObject(tmpTileObject);

		// transform object if put down like for horse transitions
		// 778 + -1 = 0 + 1422
		// 770 + -1 = 0 + 1421
		// Dont tranform this transitionslike claybowl or bana
		// DO NOT!!! 235 + -1 = 382 + 0
		var transition = TransitionImporter.GetTransition(this.target.id, -1, false, false);

		if (transition != null) {
			if (transition.newActorID == 0) {
				if (ServerSettings.DebugTransitionHelper)
					trace('TRANS: ${player.name + player.id} transform object ${target.description} in ${transition.newTargetID} / used when to put down horses');
				//  3158 + -1 = 0 + 1422 // Horse-Drawn Tire Cart + ???  -->  Empty + Escaped Horse-Drawn Cart --> must be: 3158 + -1 = 0 + 3161
				if (ServerSettings.DebugTransitionHelper) transition.traceTransition("transform: ", true);

				target.id = transition.newTargetID;
			}
		}

		this.pickUpObject = true;
		this.doAction = true;

		return true;
	}

	/*
		USE x y id i#

		USE  is for bare-hand or held-object action on target object in non-empty 
		 grid square, including picking something up (if there's no bare-handed 
		 action), and picking up a container.
		 id parameter is optional, and is used by server to differentiate 
		 intentional use-on-bare-ground actions from use actions (in case
		 where target animal moved out of the way).
		 i parameter is optional, and specifies a container slot to use a held
		 object on (for example, using a knife to slice bread sitting on a table).
	 */
	public function use(target:Int, containerIndex:Int):Bool {
		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} USE target: $target containerIndex: $containerIndex');

		// TODO intentional use with index, see description above
		// TODO noUseActor / noUseTarget

		if (this.checkIfNotMovingAndCloseEnough() == false) return false;

		if (this.tileObjectData.minPickupAge > player.age + ServerSettings.ReduceAgeNeededToPickupObjects) {
			if (ServerSettings.DebugTransitionHelper)
				trace('TRANS: ${player.name + player.id} USE: Too low age to use: target.minPickupAge: ${tileObjectData.minPickupAge} player.age: ${player.age}');
			return false;
		}

		var deadlyDistance = player.heldObject.objectData.deadlyDistance;

		// can only shoot at target with bow if not too close
		if (deadlyDistance > 1.9 && this.target.id != 0 && player.isCloseUseExact(this.target.tx, this.target.ty, 1.5)) {
			player.say('Too close...');
			return false;
		}

		// give animal a chance to escape
		if (deadlyDistance > 0 && this.target.isAnimal()) {
			if (TimeHelper.TryAnimaEscape(this.player, this.target)) return false;
		}

		var oldEnoughForTransitions = this.tileObjectData.minPickupAge <= player.age
			|| this.tileObjectData.description.toUpperCase().contains('BERRY');
		var oldEnoughForPickup = this.tileObjectData.minPickupAge <= player.age
			|| (this.target.containedObjects.length < 1 && this.tileObjectData.speedMult >= 0.98);

		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} TRANS: oldEnoughForTransitions: $oldEnoughForTransitions');

		if (this.handObjectData.tool) {
			player.connection.sendLearnedTool(this.handObjectData.parentId);
			player.held_learned = true;

			if (ServerSettings.DebugTransitionHelper) trace("TOOL LEARNED! " + this.handObjectData.parentId);
		}

		// like eating stuff from horse
		if (oldEnoughForTransitions && this.doHorseStuffPossible()) return true;

		// do actor + target = newActor + newTarget
		if (oldEnoughForTransitions && this.doTransitionIfPossible(containerIndex)) return true;

		// do nothing if tile Object is empty
		if (this.target.id == 0) return false;

		// do pickup if hand is empty
		if (oldEnoughForPickup && this.player.heldObject.id == 0 && this.swapHandAndFloorObject()) return true;

		// do container stuff
		if (oldEnoughForPickup && this.doContainerStuff(false, containerIndex)) return true;

		return false;
	}

	public function doHorseStuffPossible():Bool {
		var objId = this.player.heldObject.id;

		// 770 Riding Horse // 778 Horse-Drawn Cart // 3159 Horse-Drawn Tire Cart
		if (objId != 770 && objId != 778 && objId != 3158) return false;

		// 838 Dont eat the dam drugs! Wormless Soil Pit with Mushroom // 837 Psilocybe Mushroom
		if (tileObjectData.isDrugs()) return false;

		var lastUseActorObject = false;

		var objData = tileObjectData;
		// var tmpTileObjectId = tileObjectData.id;
		var tmpHeldObject = player.heldObject;

		var transition = null;

		if (tileObjectData.foodValue < 1) {
			transition = TransitionImporter.GetTransition(0, this.tileObjectData.id, lastUseActorObject, this.target.isLastUse());

			if (transition == null) return false;

			objData = ObjectData.getObjectData(transition.newActorID);

			if (objData.foodValue < 1) return false;
		}

		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} HORSE: Actor: ${this.player.heldObject.id} NewActor: ${objData.description}');

		if (transition != null) {
			player.heldObject = ObjectHelper.readObjectHelper(player, [transition.newActorID]);
		} else {
			player.heldObject = target;
		}

		if (GlobalPlayerInstance.doEating(player, player) == false) {
			player.heldObject = tmpHeldObject;

			return false;
		}

		if (transition == null) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} HORSE: without trans / has eaten: ${player.heldObject.description}');
			this.target = player.heldObject;
		} else {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} HORSE: with trans / has eaten: ${player.heldObject.description}');
			this.target.id = transition.newTargetID;

			DoChangeNumberOfUsesOnTarget(this.target, transition, player);
		}

		player.heldObject = tmpHeldObject;

		this.doTransition = true;
		this.doAction = true;

		return true;
	}

	public function doTransitionIfPossible(containerIndex:Int):Bool {
		var originaltarget = null;
		var originalTileObjectData = null;

		var returnValue;

		// check if you can use on item in container
		if (containerIndex >= 0) {
			if (this.target.containedObjects.length < containerIndex + 1) return false;

			originaltarget = this.target;
			originalTileObjectData = this.tileObjectData;

			this.target = this.target.containedObjects[containerIndex];
			this.tileObjectData = this.target.objectData;

			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Use on container: $containerIndex ${this.target.description}');

			returnValue = doTransitionIfPossibleHelper(originalTileObjectData.slotSize);

			this.target.TransformToDummy();

			this.target = originaltarget;
			this.tileObjectData = originalTileObjectData;
		} else {
			returnValue = doTransitionIfPossibleHelper();
		}

		return returnValue;
	}

	public function doTransitionIfPossibleHelper(containerSlotSize:Float = -1, onPlayer:Bool = false):Bool {
		var lastUseActor = false;

		if (target.objectData.isOwned) {
			if (target.isOwnedBy(player.p_id) == false) {
				if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Player is not owner of ${target.description}!');
				return false;
			}
		}

		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} handObjectData.numUses: ${handObjectData.numUses} heldObject.numberOfUses: ${this.player.heldObject.numberOfUses} ${handObjectData.description}');

		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} tileObjectData.numUses: ${tileObjectData.numUses} target.numberOfUses: ${this.target.numberOfUses} ${tileObjectData.description}');

		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} search: ${player.heldObject.parentId} + ${target.parentId}');

		var transition = TransitionImporter.GetTrans(this.player.heldObject, target);

		if (transition != null) if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} found transition!');

		// sometimes ground is -1 not 0 like for Riding Horse:
		// Should work for: 770 + -1 = 0 + 1421 // TODO -1 --> 0 in transition importer???
		// Should work for: 336 + -1 = 292 + 1101  Basket of Soil + TIME  -->  Basket + Fertile Soil Pile
		// Should not work for: 235 + -1 = 382 + 0  Clay Bowl# empty + TIME  -->  Bowl of Water + EMPTY
		if (transition == null && target.id == 0) {
			transition = TransitionImporter.GetTransition(this.player.heldObject.id, -1, lastUseActor, target.isLastUse());

			// only allow this transition if it is for switching stuff like for horses
			if (transition != null && transition.newTargetID == 0) transition = null; // TODO do right
		}

		var targetIsFloor = false;

		// check if there is a floor and no object is on the floor. otherwise the object may be overriden
		if ((transition == null) && (this.floorId != 0) && (this.tileObjectData.id == 0)) {
			transition = TransitionImporter.GetTransition(this.player.heldObject.id, this.floorId);
			if (transition != null) targetIsFloor = true;
		}

		if (transition == null) return false;

		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Found transition: actor: ${transition.actorID} target: ${transition.targetID} ');
		if (ServerSettings.DebugTransitionHelper) transition.traceTransition("TRANS: ", true);

		var newActorObjectData = ObjectData.getObjectData(transition.newActorID);
		var newTargetObjectData = ObjectData.getObjectData(transition.newTargetID);

		// if it is a reverse transition, check if it would exceed max numberOfUses
		if (transition.reverseUseActor && this.player.heldObject.numberOfUses >= newActorObjectData.numUses) {
			if (ServerSettings.DebugTransitionHelper)
				trace('TRANS: ${player.name + player.id} Actor: numberOfUses >= newTargetObjectData.numUses: ${this.player.heldObject.numberOfUses} ${newActorObjectData.numUses}');
			return false;
		}

		// if it is a reverse transition, check if it would exceed max numberOfUses
		if (transition.reverseUseTarget && this.target.numberOfUses >= newTargetObjectData.numUses) {
			if (ServerSettings.DebugTransitionHelper)
				trace('TRANS: ${player.name + player.id} Target: numberOfUses >= newTargetObjectData.numUses: ${this.target.numberOfUses} ${newTargetObjectData.numUses} try use maxUseTransition');
			transition = TransitionImporter.GetTransition(this.player.heldObject.id, this.tileObjectData.id, false, false, true);

			if (transition == null) {
				if (ServerSettings.DebugTransitionHelper)
					trace('TRANS: ${player.name + player.id} Cannot do reverse transition for taget: TileObject: ${this.target.id} numUses: ${this.target.numberOfUses} newTargetObjectData.numUses: ${newTargetObjectData.numUses}');

				return false;
			}

			// for example a well site with max stones
			// 33 + 1096 = 0 + 1096 targetRemains: true
			// 33 + 1096 = 0 + 3963 targetRemains: false (maxUseTransition)
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} use maxUseTransition');

			newActorObjectData = ObjectData.getObjectData(transition.newActorID);
			newTargetObjectData = ObjectData.getObjectData(transition.newTargetID);
		}

		// dont allow to place another floor on existing floor
		if (newTargetObjectData.floor && this.floorId != 0) return false;

		if (containerSlotSize >= 0) if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} Test if fit in container ${newTargetObjectData.description} containable: ${newTargetObjectData.containable} containSize: ${newTargetObjectData.containSize} containerSlotSize: $containerSlotSize');

		if (containerSlotSize >= 0 && (newTargetObjectData.containable == false || newTargetObjectData.containSize > containerSlotSize)) {
			if (ServerSettings.DebugTransitionHelper)
				trace('TRANS: ${player.name + player.id} Result ${newTargetObjectData.description} does not fit in container: containable: ${newTargetObjectData.containable} containSize: ${newTargetObjectData.containSize} > containerSlotSize: $containerSlotSize');
			return false;
		}

		// check if it is hungry work like cutting down a tree, using a tool or mining
		var parentActorObjectData = handObjectData.dummyParent == null ? handObjectData : handObjectData.dummyParent;
		var newParentTargetObjectData = newTargetObjectData.dummyParent == null ? newTargetObjectData : newTargetObjectData.dummyParent;
		var hungryWorkCost = Math.max(parentActorObjectData.hungryWork, newParentTargetObjectData.hungryWork);

		if (hungryWorkCost > 0) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Trans hungry Work: cost: $hungryWorkCost');

			var missingFood = Math.ceil(hungryWorkCost - (player.food_store + player.food_store_max / 2));

			if (missingFood > 0) {
				// var message = 'Its hungry work! Need ${missingFood} more food!';
				// player.connection.sendGlobalMessage(message);
				var message = 'Need ${missingFood} more food!';
				player.say(message);
				player.doEmote(Emote.homesick);

				return false;
			}

			hungryWorkCost /= 2; // half for exhaustion

			player.addFood(-hungryWorkCost);
			player.exhaustion += hungryWorkCost;
			player.doEmote(Emote.biomeRelief);
		}

		// always use alternativeTransitionOutcome from transition if there. Second use from newTargetObjectData
		var alternativeTransitionOutcome = transition.alternativeTransitionOutcome.length > 0 ? transition.alternativeTransitionOutcome : newTargetObjectData.alternativeTransitionOutcome;
		// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} TEST: ${newTargetObjectData.id} ${newTargetObjectData.description} ${newTargetObjectData.alternativeTransitionOutcome}');

		if (alternativeTransitionOutcome.length > 0) {
			// TODO reduce tool
			// TODO support more then one obj in the list
			if (0.8 > WorldMap.calculateRandomFloat()) {
				WorldMap.PlaceObjectById(tx, ty, alternativeTransitionOutcome[0]);

				this.doTransition = true;
				this.doAction = true;

				if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Place alternativeTransitionOutcome!');

				return true;
			}
		}

		// if it is a transition that picks up an object like 0 + 1422 = 778 + 0  (horse with cart) then switch the hole tile object to the hand object
		// TODO this may make trouble
		// 770 + -1 = 0 + 1421  Riding Horse + ? = 0 + Escaped Riding Horse
		// 778 + -1 = 0 + 1422  Horse-Drawn Cart
		// 778 + 4154 = 0 + 779 // Horse-Drawn Cart + Hitching Post# +wall +causeAutoOrientH -->  Empty + Hitched Horse-Drawn Cart
		// 0 + 1422 = 778 + 0 // isHorsePickupTrans: true // Empty + Escaped Horse-Drawn Cart# just released -->  Horse-Drawn Cart + Empty
		// 0 + 779 = 778 + 4154 // isHorsePickupTrans: true // Empty + Hitched Horse-Drawn Cart# +causeAutoOrientH -->  Horse-Drawn Cart + Hitching Post
		// 0 + 3963 = 33 + 1096 // Transition for Well Site should not be affected by this

		// var isHorseDropTrans = (transition.targetID == -1 && transition.newActorID == 0) && target.isPermanent() == false;
		// TODO change
		var isHorseDropTrans = transition.newActorID == 0 && player.heldObject.containedObjects.length > 0;
		// TODO better set in transition itself if it is a switch transition?
		var isHorsePickupTrans = (transition.actorID == 0 && transition.playerActor && target.containedObjects.length > 0);
		// if( || (transition.targetID == -1 && transition.newActorID == 0))

		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} isHorseDropTrans: $isHorseDropTrans isHorsePickupTrans: $isHorsePickupTrans target.isPermanent: ${target.isPermanent()} targetRemains: ${transition.targetRemains}');
		if (isHorsePickupTrans || isHorseDropTrans) {
			if (ServerSettings.DebugTransitionHelper)
				trace('TRANS: ${player.name + player.id} switch held object with tile object / This should be for transitions with horses, especially horse carts that can otherwise loose items');

			var tmpHeldObject = player.heldObject;
			player.setHeldObject(this.target);
			this.target = tmpHeldObject;

			// reset creation time, so that horses wont esape instantly
			this.target.creationTimeInTicks = TimeHelper.tick;
		} else {
			// check if not horse pickup or drop
			if (player.heldObject.containedObjects.length > newActorObjectData.numSlots) {
				if (ServerSettings.DebugTransitionHelper)
					trace('TRANS: ${player.name + player.id} New actor can only contain ${newActorObjectData.numSlots} but old actor had ${player.heldObject.containedObjects.length} contained objects!'
					+ player.heldObject.toString());

				if (player.heldObject.id == 0) {
					// TODO solve
					player.heldObject.containedObjects = [];
					trace('TRANS: ${player.name + player.id} WARNING TRANS: held object is empty and contains something!' + player.heldObject.toString());
				} else
					return false;
			}

			if (target.containedObjects.length > newTargetObjectData.numSlots) {
				if (ServerSettings.DebugTransitionHelper)
					trace('TRANS: ${player.name + player.id} New target can only contain ${newTargetObjectData.numSlots} but old target had ${target.containedObjects.length} contained objects!');

				return false;
			}
		}

		// check if biome locked or blocked
		var biome = WorldMap.worldGetBiomeId(tx, ty);
		if (newTargetObjectData.description.contains('+biomeReq4') && biome != 4) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} ${newParentTargetObjectData.name} needs ice biome!');
			return false;
		} else if (newTargetObjectData.description.contains('+biomeReq6') && biome != 6) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} ${newParentTargetObjectData.name} needs jungle biome!');
			return false;
		} else if (newTargetObjectData.description.contains('+biomeBlock4') && biome == 4) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} ${newParentTargetObjectData.name} is blocked by ice!');
			return false;
		}

		// do now the magic transformation
		// if(transition.actorID != transition.newActorID) this.pickUpObject = true; // TODO does error for bow animation but may be needed for other animations?
		player.transformHeldObject(transition.newActorID);
		this.target.id = TransformTarget(transition.newTargetID); // consider if there is an random outcome

		// reset creation / last change time
		player.heldObject.creationTimeInTicks = TimeHelper.tick;
		this.target.creationTimeInTicks = TimeHelper.tick;

		if (newTargetObjectData.floor) {
			if (targetIsFloor == false) this.target.id = 0;
			this.newFloorId = transition.newTargetID;
		} else {
			if (targetIsFloor) this.newFloorId = 0;
		}

		// transition source object id (or -1) if held object is result of a transition
		// if(transition.newActorID != this.handObject[0]) this.newTransitionSource = -1;
		// this.newTransitionSource = transition.targetID; // TODO ???

		// TODO move to SetObjectHelper
		this.target.timeToChange = ObjectHelper.CalculateTimeToChangeForObj(this.target);

		DoChangeNumberOfUsesOnActor(this.player, transition.actorID != transition.newActorID, transition.reverseUseActor);

		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} NewTileObject: ${newTargetObjectData.description} ${this.target.id} newTargetObjectData.numUses: ${newTargetObjectData.numUses}');

		// target did not change if it is same dummy
		DoChangeNumberOfUsesOnTarget(this.target, transition, player);

		ObjectHelper.DoOwnerShip(this.target, this.player);

		// if a transition is done, the MX (MAPUPDATE) needs to send a negative palyer id to indicate that its not a drop
		this.doTransition = true;
		this.doAction = true;

		return true;
	}

	// consider if there is an random outcome
	// transitions with other endings like Blooming Squash Plant // Ripe Pumpkin Plant
	// category 3221 Perhaps a Pumpkin
	public static function TransformTarget(targetId:Int):Int {
		var newTargetCategory = TransitionImporter.transitionImporter.getCategory(targetId);
		if (newTargetCategory == null || newTargetCategory.probSet == false) return targetId;

		var totalWeight:Float = 0;
		for (i in 0...newTargetCategory.ids.length) {
			var weight = newTargetCategory.weights[i];
			totalWeight += weight;
		}

		var rand = WorldMap.calculateRandomFloat() * totalWeight;
		var totalWeight:Float = 0;
		for (i in 0...newTargetCategory.ids.length) {
			var id = newTargetCategory.ids[i];
			var weight = newTargetCategory.weights[i];
			totalWeight += weight;

			if (rand <= totalWeight) return id;
		}

		return targetId;
	}

	// used for transitions and for eating food like bana or bowl of stew
	public static function DoChangeNumberOfUsesOnActor(player:GlobalPlayerInstance, idHasChanged:Bool, reverseUse:Bool):Bool {
		if (idHasChanged) return true;
		var obj = player.heldObject;

		var objectData = obj.objectData;

		if (objectData.dummyParent != null) objectData = objectData.dummyParent;

		if (reverseUse) {
			obj.numberOfUses += 1;
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} HandObject: numberOfUses: ' + obj.numberOfUses);
			return true;
		}

		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} DoChangeNumberOfUsesOnActor: ${objectData.description} ${objectData.id} useChance: ${objectData.useChance}');

		if (objectData.useChance > 0 && WorldMap.calculateRandomFloat() > objectData.useChance) return true;

		obj.numberOfUses -= 1;
		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} DoChangeNumberOfUsesOnActor: numberOfUses: ' + obj.numberOfUses);

		if (obj.numberOfUses > 0) return true;

		// check if there is a player transition like:
		// 2143 + -1 = 2144 + 0 Banana
		// 1251 + -1 = 1251 + 0 lastUseActor: false Bowl of Stew
		// 1251 + -1 = 235 + 0 lastUseActor: true Bowl of Stew

		// for example for a tool like axe lastUseActor: true
		var toolTransition = TransitionImporter.GetTransition(objectData.id, -1, true, false);

		// for example for a water bowl lastUseActor: false
		if (toolTransition == null) {
			toolTransition = TransitionImporter.GetTransition(objectData.id, -1, false, false);
		}

		if (toolTransition != null) {
			if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} Change Actor from: ${objectData.id} to ${toolTransition.newActorID}');
			obj.id = toolTransition.newActorID;
			return true;
		}

		return false;
	}

	public static function DoChangeNumberOfUsesOnTarget(obj:ObjectHelper, transition:TransitionData, player:GlobalPlayerInstance = null,
			doTrace:Bool = false) {
		var idHasChanged:Bool = transition.targetID != transition.newTargetID;
		var reverseUse = transition.reverseUseTarget;
		var objectData = obj.objectData;

		if(reverseUse == false && transition.actorID == 0){
			var lovedPlants = player == null ? [] : player.getLovedPlants();
			var isLovedFood = lovedPlants.contains(transition.targetID);

			//trace('isLovedFood1: ${obj.name}');

			if(isLovedFood){
				var useChance = ServerSettings.LovedFoodUseChance;
				var rand = WorldMap.calculateRandomFloat();

				if(objectData.numUses < 2) useChance *= 0.8;

				//trace('isLovedFood: ${obj.name}');

				if(rand > useChance){
					player.say('got an extra!', true);
					player.doEmote(Emote.happy);

					if (objectData.numUses > 1) return;
					obj.id = transition.targetID; // restore old object

					return;
				}
			}
		}

		if (objectData.numUses < 2) return;

		if (idHasChanged && objectData.numUses > 1) {
			// a Pile starts with 1 uses not with the full numberOfUses
			// if the ObjectHelper is created through a reverse use, it must be a pile or a bucket... hopefully...
			if (reverseUse) {
				if (doTrace) trace("TRANS: NEW PILE OR BUCKET?");
				obj.numberOfUses = 1;
			} else {
				//  numberOfUses = MAX // 0 + 125 = 126 + 409 // Empty + Clay Deposit -->  Clay + Clay Pit#partial
				obj.numberOfUses = objectData.numUses;
			}

			if (doTrace) trace('TRANS: ${player.name + player.id} Changed Object Type: ${objectData.description} numberOfUses: ' + obj.numberOfUses);
			return;
		}

		if (reverseUse) {
			if (obj.numberOfUses > objectData.numUses - 1) return;

			obj.numberOfUses += 1;
			if (doTrace) trace('TRANS: ${player.name + player.id} ${objectData.description} numberOfUses: ' + obj.numberOfUses);
		} else {
			// TODO wild garlic and dug wild carrot
			//var lovedPlants = player == null ? [] : player.getLovedPlants();
			//var isLovedFood = lovedPlants.contains(objectData.parentId);
			//var useChance = isLovedFood ? ServerSettings.LovedFoodUseChance : objectData.useChance;
			var useChance = objectData.useChance;
			var rand = useChance <= 0 ? -1 : WorldMap.calculateRandomFloat();

			//if (doTrace && player != null)
			//	trace('TRANS: ${player.name + player.id} isLovedFood: $isLovedFood lovedPlants: ${lovedPlants} food.parentId: ${objectData.parentId}');
			//if (doTrace) trace('TRANS: ${player.name + player.id} ${objectData.description} isLovedFood: $isLovedFood useChance: ${useChance} random: $rand');

			if (useChance <= 0 || rand < useChance) {
				obj.numberOfUses -= 1;
				if (doTrace) trace('TRANS: ${player.name + player.id} ${objectData.description} numberOfUses: ' + obj.numberOfUses);
				// Server.server.map.setObjectHelper(tx,ty, obj); // deletes ObjectHelper in case it has no uses
			}
		}
	}

	/*
		REMV x y i#

		REMV is special case of removing an object from a container.
		 i specifies the index of the container item to remove, or -1 to
		 remove top of stack. */
	public function remove(index:Int):Bool {
		if (removeObj(this.player, target, index)) {
			this.doAction = true;
			this.pickUpObject = true;
			return true;
		}

		return false;
	}

	public function removeObj(player:GlobalPlayerInstance, container:ObjectHelper, index:Int):Bool {
		if (ServerSettings.DebugTransitionHelper) trace("remove index " + index);

		// do nothing if tile Object is empty
		if (container.id == 0) return false;

		// pickup Bowl of Gooseberries???
		if (container.containedObjects.length < 1) return swapHandAndFloorObject();

		if (index >= container.containedObjects.length) return false;

		if (index < 0) index = container.containedObjects.length - 1;

		if (container.containedObjects[index].objectData.permanent == 1) return false; // this is needed if something permanent was created on the table

		player.setHeldObject(container.removeContainedObject(index));

		return true;
	}

	/*
		MX (MAP UPDATE)
		p_id is the player that was responsible for the change (in the case of an 
		object drop only), or -1 if change was not player triggered.  p_id < -1 means
		that the change was triggered by player -(p_id), but that the object
		wasn't dropped (transform triggered by a player action).
	 */
	public function sendUpdateToClient():Bool {
		// even send Player Update / PU if nothing happend. Otherwise client will get stuck
		if (this.doAction == false) {
			player.connection.send(PLAYER_UPDATE, [player.toData()]);
			player.connection.send(FRAME);

			return false;
		}

		if (ServerSettings.DebugTransitionHelper)
			trace('TRANS: ${player.name + player.id} NEW: handObjectHelper: ${player.heldObject.description} numberOfUses: ${player.heldObject.numberOfUses} '
			+ player.heldObject.toArray());
		if (ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} NEW: target: ${target.description} numberOfUses: ${target.numberOfUses} ' + target.toArray());

		Server.server.map.setFloorId(this.tx, this.ty, this.newFloorId);
		Server.server.map.setObjectHelper(this.tx, this.ty, this.target);
		this.player.move_speed = MoveHelper.calculateSpeed(player, this.tx, this.ty);

		var newTileObject = this.target.toArray();

		// TODO set right
		// player.o_transition_source_id = this.newTransitionSource;

		// if(ServerSettings.DebugTransitionHelper) trace('TRANS: ${player.name + player.id} TRANS AGE: ${player.age}');

		// this.pickUpObject = true;
		player.SetTransitionData(this.x, this.y, this.pickUpObject);

		Connection.SendTransitionUpdateToAllClosePlayers(player, tx, ty, newFloorId, newTileObject, doTransition);

		player.action = 0;

		return true;
	}
}
